package org.kosenuel.cuekeeper.w2;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
public final class W2DiscoveryChecks {
    static void check(boolean value) { if(!value) throw new AssertionError(); }
    static void checksum(byte[] reply) {
        int sum=0; for(int i=0;i<221;i++) sum+=reply[i]&255;
        ByteBuffer.wrap(reply).putShort(221,(short)sum);
    }
    static void reject(byte[] reply) {
        try { W2Discovery.decode(reply,123,"192.0.2.1"); throw new AssertionError("Accepted bad reply"); }
        catch(IllegalArgumentException expected) {}
    }
    public static void main(String[] args) {
        byte[] query=W2Discovery.query(123);
        check(query.length==42 && ByteBuffer.wrap(query).getInt(23)==123);
        byte[] reply=new byte[224]; ByteBuffer b=ByteBuffer.wrap(reply);
        reply[0]='H'; reply[1]='R'; reply[2]=1;
        b.putShort(18,(short)28); reply[20]=27; b.putShort(22,(short)193); b.putInt(24,123);
        System.arraycopy(query,27,reply,28,12);
        b.putShort(40,(short)32); b.putShort(42,(short)16); b.putShort(174,(short)145);
        byte[] name="Test sign".getBytes(StandardCharsets.UTF_16LE); System.arraycopy(name,0,reply,53,name.length);
        byte[] firmware="HD_W2 V6.02.232".getBytes(StandardCharsets.US_ASCII); System.arraycopy(firmware,0,reply,177,firmware.length);
        b.putShort(214,(short)1); reply[217]=1; b.putShort(219,(short)4096); reply[223]=(byte)0xaa; checksum(reply);
        var d=W2Discovery.decode(reply,123,"192.0.2.1");
        check(d.get("supported").equals(true) && d.get("name").equals("Test sign") && d.get("width").equals(32));
        reject(Arrays.copyOf(reply,223));
        byte[] bad=reply.clone(); bad[40]=1; reject(bad);
        bad=reply.clone(); bad[24]=1; checksum(bad); reject(bad);
        bad=reply.clone(); bad[31]^=1; checksum(bad); reject(bad);
        bad=reply.clone(); bad[21]=1; checksum(bad); reject(bad);
        bad=reply.clone(); bad[223]=0; reject(bad);
        bad=reply.clone(); ByteBuffer.wrap(bad).putShort(40,(short)64); checksum(bad);
        check(W2Discovery.decode(bad,123,"192.0.2.1").get("supported").equals(false));
        bad=reply.clone(); bad[44]=2; checksum(bad);
        check(W2Discovery.decode(bad,123,"192.0.2.1").get("supported").equals(false));
        System.out.println("10 W2 discovery checks passed.");
    }
}
