package dev.beamadb.link;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.provider.Settings;

/** Restore the user's debugging choice; Android still enforces Wi-Fi trust. */
final class AutoDebug {
 private long lastAttempt;
 private String wifi="";

 static boolean permitted(Context context){
  return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)==PackageManager.PERMISSION_GRANTED;
 }

 void restore(Context context){
  if(!context.getSharedPreferences("link",0).getBoolean("autoWifi",true) || !permitted(context))return;
  ConnectivityManager cm=context.getSystemService(ConnectivityManager.class);
  String current="";
  for(Network network:cm.getAllNetworks()){
   NetworkCapabilities caps=cm.getNetworkCapabilities(network);
   if(caps!=null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
      && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)){
    current=network.toString();break;
   }
  }
  if(current.isEmpty()){wifi="";lastAttempt=0;return;}
  if(!current.equals(wifi)){wifi=current;lastAttempt=0;}
  if(Settings.Global.getInt(context.getContentResolver(),"adb_wifi_enabled",0)==1)return;
  // One request per Wi-Fi connection. Never repeatedly dismiss a user's refusal.
  if(lastAttempt!=0)return;
  lastAttempt=android.os.SystemClock.elapsedRealtime();
  try{
   if(Settings.Global.putInt(context.getContentResolver(),"adb_wifi_enabled",1))
    android.util.Log.i("BeamADBLink","Requested Wireless debugging recovery on Wi-Fi");
  }catch(SecurityException error){
   android.util.Log.w("BeamADBLink","Wireless debugging automation permission unavailable");
  }
 }
}
