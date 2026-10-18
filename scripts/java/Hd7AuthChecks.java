package org.kosenuel.cuekeeper.w2;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.security.GeneralSecurityException;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Synthetic replies exercise integrity and correlation; no captured credentials. */
public class Hd7AuthChecks {
    static int checks;
    static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }
    static byte[] reply(Hd7Auth.Request request, byte[] key, byte[] body, int status, int flags) throws Exception {
        byte[] req=request.bytes();
        ByteBuffer b=ByteBuffer.allocate(41+body.length).order(ByteOrder.LITTLE_ENDIAN);
        b.put((byte)'D').put((byte)'H').putShort((short)b.capacity()).put((byte)24);
        b.put(new byte[8]).putInt(0).put((byte)flags);
        b.put(req,18,5).put((byte)status).put(body);
        Mac mac=Mac.getInstance("HmacMD5");
        mac.init(new SecretKeySpec(key,"HmacMD5"));
        mac.update(b.array(),0,b.position());
        b.put(mac.doFinal()).put((byte)0xaa);
        return b.array();
    }
    static void rejected(Hd7Auth.Request request, byte[] reply) throws Exception {
        try(Hd7Auth.Reply ignored=Hd7Auth.decode(request,reply,8192)) {
            throw new AssertionError("Malformed reply accepted");
        } catch(GeneralSecurityException expected) { checks++; }
    }
    public static void main(String[] args) throws Exception {
        byte[] key=MessageDigest.getInstance("MD5").digest(new byte[32]);
        byte[] sessionBytes=new byte[24];
        for(int i=0;i<sessionBytes.length;i++) sessionBytes[i]=(byte)(i+1);
        Cipher cipher=Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"));
        try(Hd7Auth.Request login=Hd7Auth.login(new char[0],"00112233445566778899aabbccddeeff","ChurchServiceTimer_Test")) {
            byte[] packet=login.bytes();
            check(packet[0]=='H' && packet[1]=='D' && packet[4]==23 && packet[22]==0,"Login framing");
            byte[] valid=reply(login,key,cipher.doFinal(sessionBytes),0,0xc1);
            try(Hd7Auth.Reply response=Hd7Auth.decode(login,valid,8192);
                Hd7Auth.Session session=response.loginSession();
                Hd7Auth.Request clock=session.command(20,new byte[14])) {
                check(response.status==0,"Login status");
                byte[] sessionKey=Arrays.copyOfRange(sessionBytes,8,24);
                byte[] ack=reply(clock,sessionKey,new byte[0],0,0xc1);
                try(Hd7Auth.Reply accepted=Hd7Auth.decode(clock,ack,8192)) {
                    check(accepted.status==0 && accepted.body().length==0,"W2 empty encrypted ACK");
                }
                byte[] altered=ack.clone(); altered[13]^=1; rejected(clock,altered);
                altered=ack.clone(); altered[18]^=1; rejected(clock,altered);
                altered=ack.clone(); altered[0]='H'; rejected(clock,altered);
                rejected(clock,Arrays.copyOf(ack,ack.length-1));
                rejected(clock,reply(clock,sessionKey,new byte[1],0,0xc1));
                try(Hd7Auth.Reply denied=Hd7Auth.decode(clock,reply(clock,new byte[32],new byte[0],-125,0xc0),8192)) {
                    check(denied.status==-125,"Signed password error");
                }
                try(Hd7Auth.Request data=session.command(3,new byte[]{1,2,3})) {
                    byte[] wire=data.bytes();
                    check((wire[17]&255)==0xc0 && wire[23]==1 && wire[25]==3,"Data remains unencrypted");
                    check(ByteBuffer.wrap(wire).order(ByteOrder.LITTLE_ENDIAN).getInt(13)==2,"Salt increments");
                }
            }
            rejected(login,reply(login,key,new byte[0],0,0xc1));
        }
        System.out.println(checks+" HD7 authentication checks passed.");
    }
}
