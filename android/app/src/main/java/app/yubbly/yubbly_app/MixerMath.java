package app.yubbly.yubbly_app;

/** Pure signal-routing mathematics, independent of Android. No source audio is retained. */
public final class MixerMath {
    private MixerMath() {}
    public static double[] gains(String mode, String curve, double seconds,
            double period, double contrast, double phase, double microHz, double depth, boolean swapped) {
        period = clamp(period, 2, 300); contrast = clamp(contrast, 1, 5);
        depth = clamp(depth, 0, .5); microHz = clamp(microHz, 0, 2);
        double u = .5 * (1 + Math.sin(2 * Math.PI * seconds / period + Math.toRadians(phase)));
        boolean power = !"linear".equals(curve);
        double a = Math.pow(power ? Math.cos(Math.PI * u / 2) : 1-u, contrast);
        double b = Math.pow(power ? Math.sin(Math.PI * u / 2) : u, contrast);
        double norm = power ? Math.sqrt(a*a+b*b) : a+b;
        a /= Math.max(norm, 1e-12); b /= Math.max(norm, 1e-12);
        double breath = depth * Math.sin(2 * Math.PI * microHz * seconds);
        // Constant headroom bounds the sum in each ear even for correlated full-scale inputs.
        double headroom = (power ? 1/Math.sqrt(2) : 1) / (1+depth);
        a *= (1+breath)*headroom; b *= (1-breath)*headroom;
        double[] result;
        switch(mode) {
            case "split": result = new double[]{1,0,0,1}; break;
            case "mono": result = new double[]{a,a,b,b}; break;
            case "together": result = new double[]{.5,.5,.5,.5}; break;
            default: result = new double[]{a,b,b,a};
        }
        if(swapped) return new double[]{result[1],result[0],result[3],result[2]};
        return result; // A-left, A-right, B-left, B-right
    }
    public static double clamp(double value, double min, double max) {
        if (!Double.isFinite(value)) return min;
        return Math.max(min,Math.min(max,value));
    }
    /** Positive offset chooses a later source fragment from B. */
    public static long secondaryPosition(long primary, int offset) { return Math.max(0,primary+offset); }
    public static float correctedSpeed(float speed,long drift) {
        if(Math.abs(drift)<25) return speed;
        return (float)(speed * (1 - clamp(drift/5000.0,-.025,.025)));
    }
}
