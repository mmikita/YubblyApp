package app.yubbly.yubbly_app;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.IBinder;
import android.os.Binder;
import android.os.Looper;
import android.os.SystemClock;
import androidx.annotation.Nullable;
import androidx.media3.common.*;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.*;
import androidx.media3.exoplayer.audio.*;
import androidx.media3.exoplayer.source.*;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;
import org.json.*;
import java.util.*;

@UnstableApi
public class PlaybackService extends MediaSessionService {
    public static PlaybackService instance;
    public static final String LOCAL_ACTION="app.yubbly.BIND_LOCAL";
    public class LocalBinder extends Binder { public PlaybackService service(){return PlaybackService.this;} }
    private final LocalBinder binder=new LocalBinder();
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final StereoMatrixProcessor matrixA=new StereoMatrixProcessor(),matrixB=new StereoMatrixProcessor();
    public ExoPlayer primary;
    private ExoPlayer secondary;
    private MediaSession mediaSession;
    private SharedPreferences prefs;
    private Map<String,Object> session=new HashMap<>(), mix=new HashMap<>();
    private Map<String,Map<String,Object>> journal=new LinkedHashMap<>();
    private boolean wanted=false,loaded=false,adjusting=false,hasPlayed=false;
    private long lastTick=0,lastSave=0,lastCorrection=0,savedPosition=0;
    private long drift=0;
    private String error="";

    @Override public void onCreate() {
        super.onCreate(); instance=this; prefs=getSharedPreferences("yubbly_native_v1",MODE_PRIVATE);
        try { session=objectMap(new JSONObject(prefs.getString("session","{}")));
            mix=map(session.get("mix")); savedPosition=prefs.getLong("position",0);
            JSONObject h=new JSONObject(prefs.getString("history","{}"));
            Iterator<String> keys=h.keys(); while(keys.hasNext()){String k=keys.next();journal.put(k,objectMap(h.getJSONObject(k)));}
        }catch(Exception ignored){session=new HashMap<>();journal=new LinkedHashMap<>();}
        primary=createPlayer(matrixA,true);secondary=createPlayer(matrixB,false);
        Player.Listener listener=new Player.Listener(){
            @Override public void onPlayerError(PlaybackException e){
                error="Nie udało się odtworzyć strumienia ("+e.getErrorCodeName()+"). Wciśnij Odtwórz, aby odświeżyć adresy YouTube.";
                wanted=false;pausePair();persist();
            }
            @Override public void onPlaybackStateChanged(int state){
                if(primary.getPlaybackState()==Player.STATE_ENDED || secondary.getPlaybackState()==Player.STATE_ENDED){
                    wanted=false;pausePair();record(true);persist();
                } else reconcile();
            }
            @Override public void onPlayWhenReadyChanged(boolean ready,int reason){
                if(!adjusting && !ready && (reason==Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS ||
                    reason==Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY)) {
                    wanted=false;pausePair();persist();
                }
            }
            @Override public void onIsPlayingChanged(boolean isPlaying){
                // A loss of audio focus/suppression must never leave language B audible alone.
                if(!primary.isPlaying()) secondary.pause();
            }
        };
        primary.addListener(listener);secondary.addListener(listener);
        Player controls=new ForwardingPlayer(primary){
            @Override public void play(){resumePair();}
            @Override public void pause(){pauseRequested();}
            @Override public void setPlayWhenReady(boolean play){if(play)resumePair();else pauseRequested();}
            @Override public void stop(){stopPair();}
            @Override public void seekTo(long positionMs){seekPair(positionMs);}
            @Override public void seekTo(int index,long positionMs){seekPair(positionMs);}
            @Override public void seekBack(){seekPair(primary.getCurrentPosition()-10000);}
            @Override public void seekForward(){seekPair(primary.getCurrentPosition()+10000);}
            @Override public void setPlaybackSpeed(float speed){mix.put("speed",(double)speed);configure(mix);}
            @Override public void setPlaybackParameters(PlaybackParameters p){mix.put("speed",(double)p.speed);configure(mix);}
        };
        PendingIntent activity=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        mediaSession=new MediaSession.Builder(this,controls).setSessionActivity(activity).build();
        // Flutter binds through our local binder, not a MediaController connection.
        // Explicitly register the session so the service owns its notification/foreground lifecycle.
        addSession(mediaSession);
        handler.post(tick);
    }
    private ExoPlayer createPlayer(StereoMatrixProcessor matrix,boolean focus){
        DefaultRenderersFactory factory=new DefaultRenderersFactory(this){
            @Override protected AudioSink buildAudioSink(Context context,boolean enableFloatOutput,boolean enableAudioTrackPlaybackParams){
                return new DefaultAudioSink.Builder(context).setEnableFloatOutput(false)
                    .setEnableAudioTrackPlaybackParams(false).setAudioProcessors(new AudioProcessor[]{matrix}).build();
            }
        };
        ExoPlayer p=new ExoPlayer.Builder(this,factory).setLoadControl(new DefaultLoadControl.Builder()
            .setBufferDurationsMs(10000,35000,1000,2000).build()).build();
        p.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),focus);
        p.setHandleAudioBecomingNoisy(focus);p.setWakeMode(C.WAKE_MODE_NETWORK);
        return p;
    }
    private MediaSource source(String url,MediaItem item){
        DefaultHttpDataSource.Factory http=new DefaultHttpDataSource.Factory()
            .setUserAgent("com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip")
            .setConnectTimeoutMs(15000).setReadTimeoutMs(20000).setAllowCrossProtocolRedirects(false)
            .setContentTypePredicate(type -> type == null || type.startsWith("audio/") || type.startsWith("video/") || type.startsWith("application/octet-stream"));
        return new ProgressiveMediaSource.Factory(new DefaultDataSource.Factory(this,http))
            .createMediaSource(item.buildUpon().setUri(url).build());
    }
    public void load(Map<String,Object> args){
        persist();stopPair();error="";hasPlayed=false;
        session=new HashMap<>(map(args.get("session")));mix=new HashMap<>(map(session.get("mix")));
        Map<String,Object> video=map(session.get("video"));
        MediaItem item=new MediaItem.Builder().setMediaId(str(video,"id",""))
            .setMediaMetadata(new MediaMetadata.Builder().setTitle(str(video,"title","YubblyApp"))
            .setArtist(str(video,"channelName","" )).setAlbumTitle(str(session,"labelA","")+" + "+str(session,"labelB","")).build()).build();
        MediaSource audioA=source(requiredUrl(args,"urlA"),item);
        String videoUrl=str(args,"videoUrl","");
        if(!videoUrl.isEmpty()) { requiredUrl(args,"videoUrl");primary.setMediaSource(new MergingMediaSource(audioA,source(videoUrl,item))); }
        else primary.setMediaSource(audioA);
        secondary.setMediaSource(source(requiredUrl(args,"urlB"),item));
        loaded=true;configure(mix);
        savedPosition=(long)number(args,"positionMs",0,0,604800000);
        primary.seekTo(savedPosition);secondary.seekTo(MixerMath.secondaryPosition(savedPosition,offset()));
        primary.prepare();secondary.prepare();wanted=true;reconcile();persist();
    }
    /**
     * googlevideo links, the app's own loopback proxy, or a local file inside
     * the app sandbox. Local M4A files let the player work fully offline.
     */
    private String requiredUrl(Map<String,Object> args,String key){
        String url=str(args,key,"");android.net.Uri u=android.net.Uri.parse(url);
        String host=u.getHost();String scheme=u.getScheme();
        boolean youtube="https".equals(scheme) && host!=null && (host.equals("googlevideo.com")||host.endsWith(".googlevideo.com"));
        boolean loopback="http".equals(scheme) && ("127.0.0.1".equals(host)||"localhost".equals(host));
        boolean local="file".equals(scheme) && isOwnedPath(u.getPath());
        if(!youtube && !loopback && !local)
            throw new IllegalArgumentException("Nieprawidłowy adres strumienia YouTube.");
        return url;
    }
    private boolean isOwnedPath(String path){
        if(path==null)return false;
        try {
            java.util.ArrayList<String> roots=new java.util.ArrayList<>();
            roots.add(getFilesDir().getCanonicalPath());
            roots.add(getCacheDir().getCanonicalPath());
            java.io.File external=getExternalFilesDir(null);
            if(external!=null)roots.add(external.getCanonicalPath());
            String resolved=new java.io.File(path).getCanonicalPath();
            for(String root:roots) if(resolved.equals(root)||resolved.startsWith(root+java.io.File.separator))return true;
        } catch (java.io.IOException ignored) {
            // A path that cannot be resolved is not one of our files.
        }
        return false;
    }
    public void configure(Map<String,Object> config){
        int previousOffset=offset();mix=new HashMap<>(config);session.put("mix",mix);
        float speed=speed();primary.setPlaybackParameters(new PlaybackParameters(speed,1));
        secondary.setPlaybackParameters(new PlaybackParameters(speed,1));
        float volume=(float)number(mix,"volume",.7,0,1);primary.setVolume(volume);secondary.setVolume(volume);
        if(loaded && previousOffset!=offset())seekPair(primary.getCurrentPosition());
        updateGains();
    }
    public void resumePair(){if(!loaded)return;error="";wanted=true;
        if(primary.getPlaybackState()==Player.STATE_ENDED || secondary.getPlaybackState()==Player.STATE_ENDED)seekPair(0);
        reconcile();}
    public void pauseRequested(){wanted=false;pausePair();persist();}
    private void pausePair(){adjusting=true;primary.pause();secondary.pause();adjusting=false;}
    public void stopPair(){wanted=false;persist();pausePair();primary.stop();secondary.stop();loaded=false;}
    public void seekPair(long position){
        long duration=primary.getDuration();long p=Math.max(0,duration>0?Math.min(position,duration):position);
        pausePair();primary.seekTo(p);secondary.seekTo(MixerMath.secondaryPosition(p,offset()));
        savedPosition=p;lastCorrection=SystemClock.elapsedRealtime();updateGains();persist();reconcile();
    }
    private void reconcile(){
        if(!loaded || !wanted){pausePair();return;}
        boolean ready=primary.getPlaybackState()==Player.STATE_READY && secondary.getPlaybackState()==Player.STATE_READY;
        adjusting=true;
        if(ready){primary.play();secondary.setPlayWhenReady(primary.isPlaying() && !inLeadIn());}
        else {primary.pause();secondary.pause();}
        adjusting=false;
    }
    private final Runnable tick=new Runnable(){public void run(){
        long now=SystemClock.elapsedRealtime();
        if(loaded){
            reconcile();
            long target=MixerMath.secondaryPosition(primary.getCurrentPosition(),offset());
            drift=inLeadIn()?0:secondary.getCurrentPosition()-target;
            if(primary.isPlaying() && (secondary.isPlaying() || inLeadIn())){
                hasPlayed=true;Map<String,Object> entry=record(false);
                long elapsed=lastTick==0?0:Math.min(250,now-lastTick);
                entry.put("listenedMs",((Number)entry.getOrDefault("listenedMs",0L)).longValue()+elapsed);
                if(!inLeadIn() && Math.abs(drift)>150 && now-lastCorrection>1500){
                    pausePair();secondary.seekTo(target);lastCorrection=now;
                } else {
                    float corrected=MixerMath.correctedSpeed(speed(),drift);
                    if(Math.abs(secondary.getPlaybackParameters().speed-corrected)>.001)
                        secondary.setPlaybackParameters(new PlaybackParameters(corrected,1));
                }
            }
            updateGains();
            if(now-lastSave>5000){persist();lastSave=now;}
        }
        lastTick=now;handler.postDelayed(this,40);
    }};
    private void updateGains(){
        double[] g=MixerMath.gains(str(mix,"mode","orbit"),str(mix,"curve","equal-power"),
            primary.getCurrentPosition()/1000.0,number(mix,"period",60,2,300),number(mix,"contrast",1,1,5),
            number(mix,"phase",0,0,360),number(mix,"microHz",.3,0,2),number(mix,"depth",.04,0,.5),Boolean.TRUE.equals(mix.get("swapped")));
        matrixA.setGains(g[0],g[1]);matrixB.setGains(inLeadIn()?0:g[2],inLeadIn()?0:g[3]);
    }
    private boolean inLeadIn(){return primary.getCurrentPosition()+offset()<0;}
    private float speed(){return(float)number(mix,"speed",1,1,5);}
    private int offset(){return(int)number(mix,"offsetMs",0,-3000,3000);}
    private Map<String,Object> record(boolean completed){
        Map<String,Object> video=map(session.get("video"));String id=str(video,"id","");
        if(id.isEmpty())return new HashMap<>();
        Map<String,Object> entry=journal.get(id);
        if(entry==null){entry=new HashMap<>(video);journal.put(id,entry);}
        entry.put("positionMs",primary.getCurrentPosition());
        entry.put("durationMs",Math.max(0,primary.getDuration()>0?primary.getDuration():((Number)video.getOrDefault("durationMs",0)).longValue()));
        entry.put("lastPlayedMs",System.currentTimeMillis());
        entry.put("complete",completed || Boolean.TRUE.equals(entry.get("complete")));
        if(journal.size()>500){String oldest=Collections.min(journal.keySet(),Comparator.comparingLong(k->((Number)journal.get(k).getOrDefault("lastPlayedMs",0)).longValue()));journal.remove(oldest);}
        return entry;
    }
    private void persist(){
        if(prefs==null)return;
        if(loaded){savedPosition=primary.getCurrentPosition();if(hasPlayed)record(false);}
        prefs.edit().putString("session",new JSONObject(session).toString()).putLong("position",savedPosition)
            .putString("history",new JSONObject(journal).toString()).apply();
    }
    public Map<String,Object> snapshot(){
        Map<String,Object> result=new HashMap<>();result.put("session",session);result.put("loaded",loaded);
        result.put("positionMs",loaded?primary.getCurrentPosition():savedPosition);
        boolean pairPlaying=primary.isPlaying()&&(secondary.isPlaying()||inLeadIn());
        result.put("durationMs",loaded?Math.max(0,primary.getDuration()):0L);result.put("playing",pairPlaying);
        result.put("buffering",wanted&&loaded&&!pairPlaying);result.put("driftMs",drift);result.put("error",error);return result;
    }
    public List<Map<String,Object>> history(){return new ArrayList<>(journal.values());}
    public void clearHistory(){journal.clear();hasPlayed=false;prefs.edit().putString("history","{}").apply();}
    @Override @Nullable public MediaSession onGetSession(MediaSession.ControllerInfo controller){
        return mediaSession;
    }
    @Override @Nullable public IBinder onBind(Intent intent){
        IBinder mediaBinder=super.onBind(intent);
        if(intent!=null && LOCAL_ACTION.equals(intent.getAction()))return binder;
        return mediaBinder;
    }
    @Override public void onTaskRemoved(Intent rootIntent){if(!wanted){stopSelf();}}
    @Override public void onDestroy(){
        persist();handler.removeCallbacksAndMessages(null);
        if(mediaSession!=null)mediaSession.release();
        if(primary!=null)primary.release();if(secondary!=null)secondary.release();instance=null;super.onDestroy();
    }
    @SuppressWarnings("unchecked") static Map<String,Object> map(Object o){return o instanceof Map?new HashMap<>((Map<String,Object>)o):new HashMap<>();}
    static String str(Map<String,Object> m,String k,String fallback){Object v=m.get(k);return v instanceof String?(String)v:fallback;}
    static double number(Map<String,Object> m,String k,double fallback,double min,double max){Object v=m.get(k);return v instanceof Number?MixerMath.clamp(((Number)v).doubleValue(),min,max):fallback;}
    static Map<String,Object> objectMap(JSONObject j)throws JSONException{
        Map<String,Object> result=new HashMap<>();Iterator<String> it=j.keys();while(it.hasNext()){String k=it.next();Object v=j.get(k);result.put(k,v instanceof JSONObject?objectMap((JSONObject)v):v==JSONObject.NULL?null:v);}return result;
    }
}
