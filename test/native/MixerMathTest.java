package app.yubbly.yubbly_app;

public final class MixerMathTest {
    private static int checks=0;
    private static void check(boolean ok,String message){checks++;if(!ok)throw new AssertionError(message);}
    private static boolean near(double a,double b){return Math.abs(a-b)<1e-8;}
    public static void main(String[] args){
        double[] s=MixerMath.gains("split","linear",5,60,1,0,0,0,false);
        check(near(s[0],1)&&near(s[1],0)&&near(s[2],0)&&near(s[3],1),"split routing");
        double[] swapped=MixerMath.gains("split","linear",5,60,1,0,0,0,true);
        check(near(swapped[0],0)&&near(swapped[1],1)&&near(swapped[2],1)&&near(swapped[3],0),"swap ears");
        double[] orbit=MixerMath.gains("orbit","linear",15,60,1,0,0,0,false);
        check(near(orbit[0],0)&&near(orbit[1],1)&&near(orbit[2],1)&&near(orbit[3],0),"orbit exchanges languages across ears");
        double[] opposite=MixerMath.gains("orbit","linear",45,60,1,0,0,0,false);
        check(near(opposite[0],1)&&near(opposite[1],0)&&near(opposite[2],0)&&near(opposite[3],1),"half-cycle reversal");
        for(String mode:new String[]{"split","orbit","mono","together"})
          for(String curve:new String[]{"linear","equal-power"})
            for(double contrast:new double[]{1,2.5,5})
              for(int i=0;i<4000;i++){
                double[] g=MixerMath.gains(mode,curve,i*.017,2,contrast,73,1.7,.5,false);
                for(double value:g)check(Double.isFinite(value)&&value>=-1e-10&&value<=1+1e-10,"finite bounded gains");
                check(g[0]+g[2]<=1+1e-10&&g[1]+g[3]<=1+1e-10,"no clipping with correlated full-scale sources");
                if(mode.equals("mono"))check(near(g[0],g[1])&&near(g[2],g[3]),"centered mono");
              }
        check(MixerMath.secondaryPosition(10,-100)==0,"negative offset boundary");
        check(MixerMath.secondaryPosition(1000,500)==1500,"positive offset semantics");
        check(MixerMath.correctedSpeed(2,100)<2,"ahead B slows");
        check(MixerMath.correctedSpeed(2,-100)>2,"late B speeds up");
        check(MixerMath.correctedSpeed(2,0)==2,"aligned B unchanged");
        System.out.println("PASS: "+checks+" mixer and synchronization assertions");
    }
}
