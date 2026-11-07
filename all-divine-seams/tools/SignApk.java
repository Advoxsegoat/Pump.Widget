// Aligns an APK like zipalign, signs it with Google's apksig, then verifies it. Signs v2 only, as
// Gradle does for minSdk 24+: every device that can install the app checks v2, and this 2017
// apksig's v1 signer relies on JDK internals that newer JDKs removed.
// Used by build-apk-offline.sh: java -cp apksig.jar SignApk.java in.apk out.apk keystore password alias minSdk
import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

public class SignApk {
    public static void main(String[] a) throws Exception {
        File in = new File(a[1] + ".aligned"), out = new File(a[1]);
        align(new File(a[0]), in);
        char[] pass = a[3].toCharArray();
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (InputStream s = new FileInputStream(a[2])) {
            ks.load(s, pass);
        }
        PrivateKey key = (PrivateKey) ks.getKey(a[4], pass);
        List<X509Certificate> certs = new ArrayList<>();
        for (Certificate c : ks.getCertificateChain(a[4])) certs.add((X509Certificate) c);

        new ApkSigner.Builder(List.of(new ApkSigner.SignerConfig.Builder("CERT", key, certs).build()))
                .setInputApk(in)
                .setOutputApk(out)
                .setMinSdkVersion(Integer.parseInt(a[5]))
                .setV1SigningEnabled(false)
                .setV2SigningEnabled(true)
                .build()
                .sign();
        in.delete();

        ApkVerifier.Result r = new ApkVerifier.Builder(out).build().verify();
        for (ApkVerifier.IssueWithParams e : r.getErrors()) System.err.println("error: " + e);
        for (ApkVerifier.IssueWithParams w : r.getWarnings()) System.err.println("warning: " + w);
        if (!r.isVerified()) System.exit(1);
        System.out.println("signed and verified (v2=" + r.isVerifiedUsingV2Scheme() + "): " + out);
    }

    // Copies the zip, padding each stored entry's local header so its data starts on a 4-byte
    // boundary. The padding is Android's alignment extra field (0xd935), which apksig keeps.
    static void align(File src, File dst) throws IOException {
        try (ZipFile zin = new ZipFile(src);
             Counting count = new Counting(new BufferedOutputStream(new FileOutputStream(dst)));
             ZipOutputStream zout = new ZipOutputStream(count)) {
            for (Enumeration<? extends ZipEntry> en = zin.entries(); en.hasMoreElements(); ) {
                ZipEntry e = en.nextElement();
                byte[] data;
                try (InputStream s = zin.getInputStream(e)) {
                    data = s.readAllBytes();
                }
                ZipEntry o = new ZipEntry(e.getName());
                o.setTime(e.getTime());
                o.setMethod(e.getMethod());
                if (e.getMethod() == ZipEntry.STORED) {
                    o.setSize(data.length);
                    o.setCompressedSize(data.length);
                    o.setCrc(e.getCrc());
                    long header = count.n + 30 + e.getName().getBytes(StandardCharsets.UTF_8).length;
                    int pad = (int) ((4 - (header + 6) % 4) % 4);
                    byte[] extra = new byte[6 + pad];
                    extra[0] = 0x35; extra[1] = (byte) 0xd9; // header id 0xd935
                    extra[2] = (byte) (2 + pad);             // data size
                    extra[4] = 4;                            // alignment
                    o.setExtra(extra);
                }
                zout.putNextEntry(o);
                zout.write(data);
                zout.closeEntry();
            }
        }
    }

    static class Counting extends FilterOutputStream {
        long n;

        Counting(OutputStream out) {
            super(out);
        }

        @Override
        public void write(int b) throws IOException {
            out.write(b);
            n++;
        }

        @Override
        public void write(byte[] b, int off, int len) throws IOException {
            out.write(b, off, len);
            n += len;
        }
    }
}
