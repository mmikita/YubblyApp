package app.yubbly.yubbly_app;

import android.content.*;
import android.os.*;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.ui.PlayerView;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.*;
import io.flutter.plugin.platform.*;
import java.util.*;

@UnstableApi
public class MainActivity extends FlutterActivity {
    private MethodChannel channel;
    private JsChallengeBridge jsChallenge;
    private PlaybackService service;
    private final List<Runnable> pending=new ArrayList<>();
    private boolean bound=false;
    private String initialLink;
    private final ServiceConnection connection=new ServiceConnection(){
        @Override public void onServiceConnected(ComponentName name,IBinder binder){
            service=((PlaybackService.LocalBinder)binder).service();
            List<Runnable> tasks=new ArrayList<>(pending);pending.clear();for(Runnable task:tasks)task.run();
        }
        @Override public void onServiceDisconnected(ComponentName name){service=null;}
    };
    @Override public void configureFlutterEngine(@NonNull FlutterEngine engine){
        super.configureFlutterEngine(engine);
        initialLink=extractLink(getIntent());
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"app.yubbly/player");
        jsChallenge=new JsChallengeBridge(this,engine.getDartExecutor().getBinaryMessenger());
        channel.setMethodCallHandler((call,result)->{
            if(call.method.equals("initialLink")){result.success(initialLink);initialLink=null;return;}
            Runnable action=()->{
                if(service==null){result.error("SERVICE","Odtwarzacz nie jest jeszcze gotowy.",null);return;}
                try{
                    Map<String,Object> args=PlaybackService.map(call.arguments);
                    switch(call.method){
                        case "state":result.success(service.snapshot());break;
                        case "history":result.success(service.history());break;
                        case "clearHistory":service.clearHistory();result.success(null);break;
                        case "load":service.load(args);result.success(null);break;
                        case "play":service.resumePair();result.success(null);break;
                        case "pause":service.pauseRequested();result.success(null);break;
                        case "stop":service.stopPair();result.success(null);break;
                        case "seek":service.seekPair(((Number)args.get("positionMs")).longValue());result.success(null);break;
                        case "configure":service.configure(args);result.success(null);break;
                        default:result.notImplemented();
                    }
                }catch(Exception e){result.error("PLAYER",e.getMessage(),null);}
            };
            if(service!=null)action.run();
            else{
                pending.add(action);
                new Handler(Looper.getMainLooper()).postDelayed(()->{
                    if(pending.remove(action))result.error("SERVICE","Nie udało się połączyć z odtwarzaczem. Uruchom aplikację ponownie.",null);
                },8000);
            }
        });
        engine.getPlatformViewsController().getRegistry().registerViewFactory("app.yubbly/video",new PlatformViewFactory(StandardMessageCodec.INSTANCE){
            @Override public PlatformView create(Context context,int id,Object args){return new VideoSurface(context);}
        });
        bound=bindService(new Intent(this,PlaybackService.class).setAction(PlaybackService.LOCAL_ACTION),connection,Context.BIND_AUTO_CREATE);
    }
    private String extractLink(Intent intent){
        if(intent==null)return null;
        if(Intent.ACTION_VIEW.equals(intent.getAction()))return intent.getDataString();
        if(Intent.ACTION_SEND.equals(intent.getAction()))return intent.getStringExtra(Intent.EXTRA_TEXT);
        return null;
    }
    @Override protected void onNewIntent(@NonNull Intent intent){super.onNewIntent(intent);setIntent(intent);
        String link=extractLink(intent);if(link!=null){if(channel!=null)channel.invokeMethod("incoming",link);else initialLink=link;}}
    @Override protected void onDestroy(){
        if(channel!=null)channel.setMethodCallHandler(null);
        if(jsChallenge!=null){jsChallenge.dispose();jsChallenge=null;}
        if(bound){unbindService(connection);bound=false;}service=null;super.onDestroy();
    }
    private static class VideoSurface implements PlatformView {
        private final PlayerView view;
        private final Handler handler=new Handler(Looper.getMainLooper());
        private boolean disposed=false;
        private final Runnable attach=new Runnable(){public void run(){
            if(disposed)return;
            if(PlaybackService.instance!=null)view.setPlayer(PlaybackService.instance.primary);
            else handler.postDelayed(this,150);
        }};
        VideoSurface(Context context){view=new PlayerView(context);view.setUseController(false);handler.post(attach);}
        @Override public View getView(){return view;}
        @Override public void dispose(){disposed=true;handler.removeCallbacksAndMessages(null);view.setPlayer(null);}
    }
}
