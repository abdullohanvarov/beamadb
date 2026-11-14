package dev.beamadb.link;

import android.app.*;
import android.content.*;
import android.net.*;
import android.net.nsd.*;
import android.os.IBinder;
import java.io.*;
import java.net.*;
import java.security.MessageDigest;
import java.security.cert.*;
import javax.net.ssl.*;
import org.json.JSONObject;

public class Link extends Service implements NsdManager.DiscoveryListener {
 private volatile boolean running;
 private volatile int adbPort;
 private volatile String ownService="";
 private final java.util.concurrent.ConcurrentHashMap<String,Integer> localPorts=new java.util.concurrent.ConcurrentHashMap<>();
 private final java.util.ArrayDeque<NsdServiceInfo> pendingServices=new java.util.ArrayDeque<>();
 private boolean resolving;
 private volatile Socket transport;
 private Thread worker, heartbeat;
 private NsdManager nsd;
 private ConnectivityManager cm;
 private final AutoDebug autoDebug=new AutoDebug();
 private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback(){
  public void onAvailable(Network n){wake();}
  public void onLost(Network n){close(transport);wake();}
 };
 private synchronized void wake(){notifyAll();}
 private static void close(Socket socket){if(socket!=null)try{socket.close();}catch(IOException ignored){}}
 private void notice(String message){
  android.util.Log.i("BeamADBLink",message);
  Notification n=new Notification.Builder(this,"connection").setSmallIcon(android.R.drawable.stat_notify_sync)
    .setContentTitle("BeamADB Link").setContentText("Remote access enabled · Manage from BeamADB desktop").setOngoing(true)
    .setContentIntent(PendingIntent.getActivity(this,0,new Intent(this,Setup.class),PendingIntent.FLAG_IMMUTABLE)).build();
  startForeground(1,n);
 }
 public IBinder onBind(Intent i){return null;}
 public void onCreate(){
  super.onCreate();
  getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel("connection","Connection",NotificationManager.IMPORTANCE_MIN));
  notice("Looking for wireless debugging");
  running=true;
  nsd=getSystemService(NsdManager.class);
  nsd.discoverServices("_adb-tls-connect._tcp",NsdManager.PROTOCOL_DNS_SD,this);
  cm=getSystemService(ConnectivityManager.class);cm.registerDefaultNetworkCallback(network);
  worker=new Thread(this::runLink,"beamadb-link");worker.start();
  heartbeat=new Thread(this::reportPresence,"beamadb-presence");heartbeat.start();
 }
 public int onStartCommand(Intent intent,int flags,int id){close(transport);wake();return START_STICKY;}
 public void onDestroy(){
  running=false;close(transport);wake();worker.interrupt();heartbeat.interrupt();
  cm.unregisterNetworkCallback(network);
  try{nsd.stopServiceDiscovery(this);}catch(IllegalArgumentException ignored){}
  super.onDestroy();
 }
 public void onDiscoveryStarted(String t){}
 public void onDiscoveryStopped(String t){}
 public void onStartDiscoveryFailed(String t,int e){notice("Discovery unavailable. Restart Link to retry.");}
 public void onStopDiscoveryFailed(String t,int e){}
 public void onServiceLost(NsdServiceInfo s){
  localPorts.remove(s.getServiceName());
  if(s.getServiceName().equals(ownService)){adbPort=0;ownService="";wake();}
 }
 public void onServiceFound(NsdServiceInfo s){
  synchronized(pendingServices){pendingServices.add(s);}
  resolveNext();
 }
 private void resolveNext(){
  NsdServiceInfo s;
  synchronized(pendingServices){
   if(resolving || (s=pendingServices.poll())==null)return;
   resolving=true;
  }
  nsd.resolveService(s,new NsdManager.ResolveListener(){
   private void next(){synchronized(pendingServices){resolving=false;}resolveNext();}
   public void onResolveFailed(NsdServiceInfo service,int error){next();}
   public void onServiceResolved(NsdServiceInfo service){
    try{
     InetAddress addr=service.getHost();
     if(addr!=null && (addr.isLoopbackAddress() || NetworkInterface.getByInetAddress(addr)!=null)){
      localPorts.put(service.getServiceName(),service.getPort());wake();
     }
    }catch(SocketException ignored){}finally{next();}
   }
  });
 }
 private void findAdbPort(){
  adbPort=0;ownService="";
  // The paired desktop explicitly enables this authenticated ADB listener.
  // Probing it does not enable TCP mode or expose a new listener.
  try(Socket probe=new Socket()){
   probe.connect(new InetSocketAddress("127.0.0.1",45885),500);
   adbPort=45885;return;
  }catch(IOException ignored){}

  for(java.util.Map.Entry<String,Integer> candidate:localPorts.entrySet()){
   try(Socket probe=new Socket()){
    probe.connect(new InetSocketAddress("127.0.0.1",candidate.getValue()),500);
    ownService=candidate.getKey();adbPort=candidate.getValue();return;
   }catch(IOException ignored){}
  }
 }
 private static SSLSocket pinned(Socket socket,String host,int port,String pin)throws Exception{
  X509TrustManager trust=new X509TrustManager(){
   public X509Certificate[] getAcceptedIssuers(){return new X509Certificate[0];}
   public void checkClientTrusted(X509Certificate[] c,String a)throws CertificateException{throw new CertificateException();}
   public void checkServerTrusted(X509Certificate[] c,String a)throws CertificateException{
    try{
     StringBuilder hex=new StringBuilder();
     for(byte b:MessageDigest.getInstance("SHA-256").digest(c[0].getEncoded()))hex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
     if(!pin.contentEquals(hex))throw new CertificateException("Peer certificate changed");
    }catch(java.security.GeneralSecurityException e){throw new CertificateException(e);}
   }
  };
  SSLContext context=SSLContext.getInstance("TLS");context.init(null,new TrustManager[]{trust},null);
  SSLSocket tls=(SSLSocket)context.getSocketFactory().createSocket(socket,host,port,true);
  tls.setSoTimeout(30000);tls.startHandshake();return tls;
 }
 private static void copy(Socket from,Socket to){
  try{InputStream in=from.getInputStream();OutputStream out=to.getOutputStream();byte[] buf=new byte[32768];int n;
   while((n=in.read(buf))!=-1)out.write(buf,0,n);
  }catch(IOException e){android.util.Log.i("BeamADBLink","Stream closed: "+e.getClass().getSimpleName()+": "+e.getMessage());}finally{close(from);close(to);}
 }
 private void reportPresence(){
  while(running){
   try(Socket socket=new Socket()){
    JSONObject cfg=new JSONObject(getSharedPreferences("link",0).getString("config","{}"));
    String host=cfg.getString("host");int port=cfg.getInt("port");
    socket.connect(new InetSocketAddress(host,port),8000);
    try(SSLSocket tls=pinned(socket,host,port,cfg.getString("pin"))){
     tls.getOutputStream().write(("STATUS "+cfg.getString("token")+(cfg.has("channel")?" CHANNEL "+cfg.getString("channel"):"")+"\n").getBytes("US-ASCII"));
     tls.getInputStream().read();
    }
   }catch(Exception e){android.util.Log.w("BeamADBLink","Presence retry: "+e.getClass().getSimpleName());}
   synchronized(this){if(running)try{wait(12000);}catch(InterruptedException ignored){}}
  }
 }
 private void session()throws Exception{
  JSONObject cfg=new JSONObject(getSharedPreferences("link",0).getString("config","{}"));
  String host=cfg.getString("host");int port=cfg.getInt("port");
  try(Socket socket=new Socket()){
   transport=socket;socket.connect(new InetSocketAddress(host,port),10000);
   try(SSLSocket outer=pinned(socket,host,port,cfg.getString("pin"))){
    outer.getOutputStream().write((cfg.getString("token")+(cfg.has("channel")?" CHANNEL "+cfg.getString("channel"):"")+"\n").getBytes("US-ASCII"));
    InputStream in=outer.getInputStream();if(in.read()!='O'||in.read()!='K'||in.read()!=10)return;
    try(SSLSocket inner=pinned(outer,"beamadb-peer",port,cfg.getString("peer"));Socket phone=new Socket()){
     phone.connect(new InetSocketAddress("127.0.0.1",adbPort),3000);
     inner.getOutputStream().write((cfg.getString("proof")+"\n").getBytes("US-ASCII"));
     outer.setSoTimeout(0);inner.setSoTimeout(0);
     notice("Tunnel connected to Ubuntu");
     Thread upload=new Thread(()->copy(phone,inner));upload.start();copy(inner,phone);upload.join();
    }
   }
  }finally{transport=null;}
 }
 private void runLink(){
  while(running){
   try{
    autoDebug.restore(this);
    findAdbPort();
    if(adbPort>0){notice("Waiting for Ubuntu");session();}
    else notice("Waiting for this phone’s wireless debugging service");
   }catch(Exception e){android.util.Log.w("BeamADBLink","Tunnel retry: "+e.getClass().getSimpleName()+": "+e.getMessage());}
   synchronized(this){if(running)try{wait(3000);}catch(InterruptedException ignored){}}
  }
 }
}
