package org.kosenuel.churchservicetimer.w2;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

/** Strict decoder for the parameter selection physically verified on W2. */
public final class W2Discovery {
    public static final int PORT = 6101;
    private static final byte[] QUERY = {0,12,(byte)255,13,(byte)236,(byte)169,97,0,0,(byte)198,0,1};
    private W2Discovery() {}
    public static byte[] query(int sequence) {
        ByteBuffer b = ByteBuffer.allocate(42).order(ByteOrder.BIG_ENDIAN);
        b.put(new byte[]{'H','T',0,27}).putShort((short)42).put((byte)27);
        b.put(new byte[16]).putInt(sequence).put(QUERY);
        int sum=0;
        for(int i=0;i<39;i++) sum+=b.get(i)&255;
        return b.putShort((short)sum).put((byte)0xaa).array();
    }
    public static Map<String,Object> decode(byte[] wire, int sequence, String address) {
        if(wire.length!=224) throw new IllegalArgumentException("Unsupported discovery length");
        ByteBuffer b=ByteBuffer.wrap(wire).order(ByteOrder.BIG_ENDIAN);
        int sum=0;
        for(int i=0;i<wire.length-3;i++) sum+=wire[i]&255;
        if(wire[0]!='H'||wire[1]!='R'||b.getShort(18)!=28||wire[20]!=27||wire[21]!=0||
                (b.getShort(22)&65535)!=193||b.getInt(24)!=sequence||
                (b.getShort(221)&65535)!=(sum&65535)||wire[223]!=(byte)0xaa)
            throw new IllegalArgumentException("Invalid discovery reply");
        // Other presence masks change all offsets: never guess at their layout.
        if(!Arrays.equals(Arrays.copyOfRange(wire,28,40),QUERY))
            throw new IllegalArgumentException("Unsupported parameter selection");
        StringBuilder id=new StringBuilder();
        for(int i=2;i<18;i++) id.append(String.format(java.util.Locale.ROOT,"%02x",wire[i]&255));
        String name=new String(wire,53,72,StandardCharsets.UTF_16LE).split("\u0000",2)[0].trim();
        String firmware=new String(wire,177,32,StandardCharsets.US_ASCII).split("\u0000",2)[0];
        int width=b.getShort(40)&65535,height=b.getShort(42)&65535,color=wire[44]&255;
        int model=b.getShort(174)&65535,protocol=b.getShort(214)&65535,chunk=b.getShort(219)&65535;
        boolean supported=width==32&&height==16&&color==0&&model==145&&protocol==1&&
                wire[217]==1&&chunk>=393&&chunk<=4096&&firmware.equals("HD_W2 V6.02.232");
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("id",id.toString()); result.put("name",name.isEmpty()?"W2 display":name);
        result.put("address",address); result.put("firmware",firmware);
        result.put("width",width); result.put("height",height); result.put("color",color);
        result.put("model",model); result.put("chunk",chunk); result.put("supported",supported);
        result.put("pwdComplexity",wire[218]&255);
        return result;
    }
}
