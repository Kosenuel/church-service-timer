package org.kosenuel.churchservicetimer.w2;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.CharBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.Locale;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** HD7 wire codec. No network I/O, logging, or credential persistence. */
public final class Hd7Auth {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final char[] PASSWORD_SUFFIX =
            "64ACFEB8B6FE4EF082DB8F3CD428EB20".toCharArray();
    private Hd7Auth() {}

    public static final class Request implements AutoCloseable {
        private final byte[] wire, key;
        private final int command, messageId;
        private boolean closed;
        private Request(byte[] wire, byte[] key, int command, int messageId) {
            this.wire = wire; this.key = key.clone();
            this.command = command; this.messageId = messageId;
        }
        public byte[] bytes() { checkOpen(); return wire.clone(); }
        private void checkOpen() {
            if (closed) throw new IllegalStateException("Request closed");
        }
        @Override public void close() {
            Arrays.fill(key, (byte) 0); Arrays.fill(wire, (byte) 0); closed = true;
        }
    }

    public static final class Reply implements AutoCloseable {
        public final int status, flags;
        private final byte[] plaintext;
        private Reply(int status, int flags, byte[] plaintext) {
            this.status = status; this.flags = flags; this.plaintext = plaintext;
        }
        public byte[] body() { return plaintext.clone(); }
        public Session loginSession() throws GeneralSecurityException {
            if (status != 0) throw new GeneralSecurityException("Controller rejected login: " + status);
            if ((flags & 1) == 0 || plaintext.length != 24)
                throw new GeneralSecurityException("Invalid login result");
            return new Session(Arrays.copyOfRange(plaintext, 0, 8),
                    Arrays.copyOfRange(plaintext, 8, 24));
        }
        @Override public void close() { Arrays.fill(plaintext, (byte) 0); }
    }

    public static final class Session implements AutoCloseable {
        private final byte[] id, key;
        private int salt;
        private boolean closed;
        private Session(byte[] id, byte[] key) { this.id = id; this.key = key; }
        public synchronized Request command(int command, byte[] plaintext)
                throws GeneralSecurityException {
            if (closed) throw new IllegalStateException("Session closed");
            if (command <= 0 || command > 127) throw new IllegalArgumentException("Invalid command");
            if (salt == Integer.MAX_VALUE) throw new GeneralSecurityException("Session sequence exhausted");
            return packet(command, plaintext, id, key, ++salt);
        }
        @Override public synchronized void close() {
            Arrays.fill(id, (byte) 0); Arrays.fill(key, (byte) 0); closed = true;
        }
    }

    public static Request login(char[] password, String installationId, String applicationName)
            throws GeneralSecurityException {
        if (password == null) throw new IllegalArgumentException("Password required");
        byte[] key = passwordKey(password);
        try { return loginWithDerivedKey(key, installationId, applicationName); }
        finally { Arrays.fill(key, (byte) 0); }
    }

    // Package scope supports diagnostics without placing credentials on a command line.
    static Request loginWithDerivedKey(byte[] key, String installationId, String applicationName)
            throws GeneralSecurityException {
        if (key.length != 16 || installationId == null || !installationId.matches("[0-9a-fA-F]{32}") ||
                applicationName == null || !applicationName.matches("[A-Za-z0-9._-]{1,80}"))
            throw new IllegalArgumentException("Invalid login arguments");
        String timestamp = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.ROOT).format(new Date());
        byte[] log = (installationId + "__" + timestamp + "_" + applicationName).getBytes(StandardCharsets.UTF_8);
        byte[] identity = md5(installationId.getBytes(StandardCharsets.UTF_8));
        byte[] plaintext = new byte[4 + log.length];
        try {
            for (int group = 0; group < 4; group++) {
                int sum = 0;
                for (int i = 0; i < 4; i++) sum += identity[group * 4 + i] & 255;
                plaintext[group] = (byte) sum;
            }
            System.arraycopy(log, 0, plaintext, 4, log.length);
            return packet(0, plaintext, new byte[8], key, 0);
        } finally {
            Arrays.fill(log, (byte) 0); Arrays.fill(identity, (byte) 0); Arrays.fill(plaintext, (byte) 0);
        }
    }

    private static byte[] passwordKey(char[] password) throws GeneralSecurityException {
        if (password.length == 0) return md5(new byte[32]);
        char[] joined = new char[password.length + PASSWORD_SUFFIX.length];
        ByteBuffer encoded = null;
        byte[] input = null;
        try {
            System.arraycopy(password, 0, joined, 0, password.length);
            System.arraycopy(PASSWORD_SUFFIX, 0, joined, password.length, PASSWORD_SUFFIX.length);
            encoded = StandardCharsets.UTF_8.encode(CharBuffer.wrap(joined));
            input = new byte[encoded.remaining()]; encoded.get(input);
            return md5(input);
        } finally {
            Arrays.fill(joined, '\0');
            if (input != null) Arrays.fill(input, (byte) 0);
            if (encoded != null && encoded.hasArray()) Arrays.fill(encoded.array(), (byte) 0);
        }
    }

    private static Request packet(int command, byte[] plaintext, byte[] session, byte[] key, int salt)
            throws GeneralSecurityException {
        if (plaintext == null || session.length != 8 || key.length != 16)
            throw new IllegalArgumentException("Invalid packet arguments");
        boolean encrypt = command != 3 && command != 25;
        byte[] body = encrypt ? aes(Cipher.ENCRYPT_MODE, key, plaintext) : plaintext.clone();
        byte[] tag = null;
        try {
            int length = body.length + 40;
            if (length > 32767) throw new IllegalArgumentException("Packet too large");
            int messageId = RANDOM.nextInt();
            byte[] wire = new byte[length];
            ByteBuffer b = ByteBuffer.wrap(wire).order(ByteOrder.LITTLE_ENDIAN);
            b.put((byte)'H').put((byte)'D').putShort((short)length).put((byte)23);
            b.put(session).putInt(salt).put((byte)(encrypt ? 0xc1 : 0xc0)).putInt(messageId);
            b.put((byte)command).put(body);
            tag = hmac(key, wire, length - 17);
            b.put(tag).put((byte)0xaa);
            return new Request(wire, key, command, messageId);
        } finally {
            Arrays.fill(body, (byte)0);
            if (tag != null) Arrays.fill(tag, (byte)0);
        }
    }

    /** Verify the UDP peer separately; pass exact datagram bytes, excluding buffer tail. */
    public static Reply decode(Request request, byte[] wire, int maxPacketLength)
            throws GeneralSecurityException {
        request.checkOpen();
        if (wire == null || wire.length < 41 || wire.length > maxPacketLength || wire.length > 32767)
            throw new GeneralSecurityException("Invalid response length");
        ByteBuffer b = ByteBuffer.wrap(wire).order(ByteOrder.LITTLE_ENDIAN);
        if (wire[0] != 'D' || wire[1] != 'H' || (b.getShort(2)&65535) != wire.length ||
                wire[4] != 24 || wire[wire.length-1] != (byte)0xaa)
            throw new GeneralSecurityException("Invalid response framing");
        if ((wire[22]&255) != request.command || b.getInt(18) != request.messageId)
            throw new GeneralSecurityException("Unmatched response");
        int status = wire[23], flags = wire[17]&255;
        byte[] verificationKey = status == 0 ? request.key : new byte[32];
        byte[] expected = null, supplied = null, body = null;
        try {
            expected = hmac(verificationKey, wire, wire.length-17);
            supplied = Arrays.copyOfRange(wire, wire.length-17, wire.length-1);
            if (!MessageDigest.isEqual(expected, supplied))
                throw new GeneralSecurityException("Response authentication failed");
            if (status != 0) return new Reply(status, flags, new byte[0]);
            body = Arrays.copyOfRange(wire, 24, wire.length-17);
            // W2 acknowledgements can have an empty body with the encryption bit set.
            // Their status and entire header have already passed HMAC verification.
            if ((flags&1) != 0 && body.length%16 != 0)
                throw new GeneralSecurityException("Invalid encrypted body");
            byte[] plain = (flags&1) != 0 && body.length > 0
                    ? aes(Cipher.DECRYPT_MODE, request.key, body) : body.clone();
            if (request.command == 0 && ((flags&1) == 0 || plain.length != 24)) {
                Arrays.fill(plain, (byte)0);
                throw new GeneralSecurityException("Invalid login result");
            }
            return new Reply(status, flags, plain);
        } finally {
            if (status != 0) Arrays.fill(verificationKey, (byte)0);
            if (expected != null) Arrays.fill(expected, (byte)0);
            if (supplied != null) Arrays.fill(supplied, (byte)0);
            if (body != null) Arrays.fill(body, (byte)0);
        }
    }

    private static byte[] aes(int mode, byte[] key, byte[] input) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(mode, new SecretKeySpec(key, "AES"));
        return cipher.doFinal(input);
    }
    private static byte[] hmac(byte[] key, byte[] bytes, int count) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacMD5");
        mac.init(new SecretKeySpec(key, "HmacMD5")); mac.update(bytes, 0, count);
        return mac.doFinal();
    }
    private static byte[] md5(byte[] bytes) throws GeneralSecurityException {
        return MessageDigest.getInstance("MD5").digest(bytes);
    }
}
