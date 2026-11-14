package dev.beamadb.link;
import android.app.*;
import android.content.*;
import android.os.Bundle;
import android.graphics.Insets;
import android.view.Window;
import android.view.WindowInsets;
import android.widget.*;
import org.json.JSONObject;
import java.io.InputStream;
public class Setup extends Activity {
 TextView info;
 void status(String s){info.setText(s);}
 public void onCreate(Bundle state){
  super.onCreate(state);
  requestWindowFeature(Window.FEATURE_NO_TITLE);
  LinearLayout box=new LinearLayout(this);box.setOrientation(1);
  int padding=Math.round(24*getResources().getDisplayMetrics().density);
  box.setPadding(padding,padding,padding,padding);
  box.setOnApplyWindowInsetsListener((view,insets)->{
   Insets bars=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
   view.setPadding(padding+bars.left,padding+bars.top,padding+bars.right,padding+bars.bottom);
   return insets;
  });
  setContentView(box);
  info=new TextView(this);box.addView(info);
  status(getSharedPreferences("link",0).getBoolean("enabled",false)?"BeamADB is linked. Manage your connection from the desktop app.":"First pair Ubuntu in Wireless debugging. Then import the private invitation from BeamADB.");
  Button open=new Button(this);open.setText("Import BeamADB invitation");box.addView(open);
  open.setOnClickListener(v->startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE),1));
  Button debug=new Button(this);debug.setText("Developer options");box.addView(debug);debug.setOnClickListener(v->startActivity(new Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)));
  Switch automatic=new Switch(this);automatic.setText("Reconnect automatically on trusted Wi-Fi");
  automatic.setChecked(getSharedPreferences("link",0).getBoolean("autoWifi",true));box.addView(automatic);
  automatic.setOnCheckedChangeListener((button,checked)->getSharedPreferences("link",0).edit().putBoolean("autoWifi",checked).apply());
  TextView automationInfo=new TextView(this);
  automationInfo.setText(AutoDebug.permitted(this)?"Wi-Fi recovery permission granted. Unlock once after restarting. New Wi-Fi networks may require Android's debugging approval.":"Wi-Fi recovery needs a one-time permission grant from your paired computer.");box.addView(automationInfo);
  Button stop=new Button(this);stop.setText("Unlink this phone");box.addView(stop);
  stop.setOnClickListener(v->{getSharedPreferences("link",0).edit().clear().commit();stopService(new Intent(this,Link.class));status("Unlinked");});

  if(getSharedPreferences("link",0).getBoolean("enabled",false)){startForegroundService(new Intent(this,Link.class));if(getIntent().getBooleanExtra("background",false))finish();}
 }
 protected void onActivityResult(int req,int result,Intent data){
  super.onActivityResult(req,result,data);
  if(req!=1||result!=RESULT_OK||data==null)return;
  try(InputStream in=getContentResolver().openInputStream(data.getData())){
   byte[] buf=new byte[4097];int n=0,r;
   while(n<buf.length && (r=in.read(buf,n,buf.length-n))>0)n+=r;
   if(n==buf.length)throw new Exception();
   Provision.save(this,new String(buf,0,n,"UTF-8"));
   startForegroundService(new Intent(this,Link.class));status("BeamADB is linked. Manage your connection from the desktop app.");
  }catch(Exception e){status("Could not read a valid BeamADB invitation.");}
 }
}
