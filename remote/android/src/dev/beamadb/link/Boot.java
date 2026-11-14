package dev.beamadb.link;
import android.content.*;
public class Boot extends BroadcastReceiver {
 public void onReceive(Context c, Intent i) {
  if(Intent.ACTION_BOOT_COMPLETED.equals(i.getAction()) && c.getSharedPreferences("link",0).getBoolean("enabled",false))
   c.startForegroundService(new Intent(c, Link.class));
 }
}
