package dev.beamadb.link;
import android.content.*;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import org.json.JSONObject;
import java.io.*;

/** Shell-only provisioning: DUMP is a platform permission unavailable to ordinary apps. */
public class Provision extends ContentProvider {
 public boolean onCreate(){return true;}
 public String getType(Uri uri){return "application/json";}
 public static void save(Context context,String text)throws Exception{
  JSONObject cfg=new JSONObject(text);
  for(String key:new String[]{"pin","peer","token","proof"})
   if(!cfg.getString(key).matches("[0-9a-f]{64}"))throw new Exception("Invalid invitation");
  if(cfg.has("channel")&&!cfg.getString("channel").matches("[0-9a-f]{64}"))throw new Exception("Invalid channel");
  if(cfg.getString("host").isEmpty()||cfg.getInt("port")<1||cfg.getInt("port")>65535)throw new Exception("Invalid address");
  if(!context.getSharedPreferences("link",0).edit().putString("config",cfg.toString()).putBoolean("enabled",true).commit())throw new IOException();
 }
 public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
  if(!"w".equals(mode))throw new FileNotFoundException("Write only");
  try{
   ParcelFileDescriptor[] pipe=ParcelFileDescriptor.createPipe();
   new Thread(()->{
    try(InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(pipe[0])){
     ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buf=new byte[1024];int n;
     while((n=in.read(buf))!=-1){out.write(buf,0,n);if(out.size()>4096)throw new IOException();}
     save(getContext(),out.toString("UTF-8"));
    }catch(Exception e){android.util.Log.w("BeamADBLink","Provisioning rejected");}
   },"beamadb-provision").start();
   return pipe[1];
  }catch(IOException e){throw new FileNotFoundException("Provisioning unavailable");}
 }
 public Cursor query(Uri uri,String[] columns,String selection,String[] args,String order){
  MatrixCursor result=new MatrixCursor(new String[]{"enabled","channel"});
  String channel="";
  try{channel=new JSONObject(getContext().getSharedPreferences("link",0).getString("config","{}")).optString("channel","");}catch(Exception ignored){}
  result.addRow(new Object[]{getContext().getSharedPreferences("link",0).getBoolean("enabled",false)?1:0,channel});return result;
 }
 public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}
 public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
 public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}
}
