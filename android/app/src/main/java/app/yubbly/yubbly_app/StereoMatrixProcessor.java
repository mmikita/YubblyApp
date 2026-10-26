package app.yubbly.yubbly_app;

import java.nio.ByteBuffer;
import androidx.media3.common.C;
import androidx.media3.common.audio.BaseAudioProcessor;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;

/** Fold each source to mono, route it to L/R, and smooth live gain changes over 10 ms. */
@UnstableApi
public final class StereoMatrixProcessor extends BaseAudioProcessor {
    private volatile double targetLeft=0, targetRight=0;
    private double left=0,right=0;
    public void setGains(double l,double r) { targetLeft=l; targetRight=r; }
    @Override protected AudioFormat onConfigure(AudioFormat input) throws UnhandledAudioFormatException {
        if(input.encoding!=C.ENCODING_PCM_16BIT || input.channelCount<1 || input.channelCount>8) {
            throw new AudioProcessor.UnhandledAudioFormatException(input);
        }
        return new AudioFormat(input.sampleRate,2,C.ENCODING_PCM_16BIT);
    }
    @Override public void queueInput(ByteBuffer input) {
        int channels=inputAudioFormat.channelCount;
        int frames=input.remaining()/(2*channels);
        ByteBuffer output=replaceOutputBuffer(frames*4);
        double alpha=1-Math.exp(-1.0/(.010*inputAudioFormat.sampleRate));
        for(int f=0; f<frames; f++) {
            double mono=0;
            for(int c=0;c<channels;c++) mono+=input.getShort();
            mono/=channels;
            left+=alpha*(targetLeft-left); right+=alpha*(targetRight-right);
            output.putShort((short)Math.round(MixerMath.clamp(mono*left,-32768,32767)));
            output.putShort((short)Math.round(MixerMath.clamp(mono*right,-32768,32767)));
        }
        output.flip();
    }
    @Override protected void onReset() { left=0;right=0; }
}
