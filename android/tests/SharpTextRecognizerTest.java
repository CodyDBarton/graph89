import com.graph89.emulationcore.SharpTextRecognizer;
import java.util.List;

/** Standalone regression checks; synthetic glyphs, no calculator ROM required. */
public final class SharpTextRecognizerTest {
    private static final int WIDTH = 160, HEIGHT = 100;
    private static final int[] A = {28, 34, 34, 62, 34, 34, 34, 0};
    private static final int[] B = {60, 34, 34, 60, 34, 34, 60, 0};
    private static void font(byte[] data, char c, int[] rows) {
        int p = (256 + c) * 12;
        data[p] = 6; data[p + 1] = 8;
        for (int y = 0; y < rows.length; ++y) data[p + 2 + y] = (byte)(rows[y] << 2);
    }
    private static void draw(boolean[] pixels, int x, int y, int[] rows, boolean inverse) {
        for (int j = 0; j < rows.length; ++j) for (int i = 0; i < 6 && x + i < WIDTH; ++i)
            pixels[(y + j) * WIDTH + x + i] = (((rows[j] >> (5 - i)) & 1) != 0) != inverse;
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void pair(SharpTextRecognizer recognizer, boolean[] pixels, int x, int y, boolean inverse) {
        List<SharpTextRecognizer.Cell> cells = recognizer.recognize(pixels, WIDTH, HEIGHT);
        check(cells.size() == 2, "Expected only the two text cells, got " + cells.size());
        check(cells.get(0).glyph.character == 'A' && cells.get(1).glyph.character == 'B', "Text identity");
        check(cells.get(0).x == x && cells.get(1).x == x + 6 && cells.get(0).y == y, "Text position");
        check(cells.get(0).inverse == inverse && cells.get(1).inverse == inverse, "Selection polarity");
    }
    public static void main(String[] args) {
        byte[] fonts = new byte[3 * 256 * 12]; font(fonts, 'A', A); font(fonts, 'B', B);
        SharpTextRecognizer r = new SharpTextRecognizer(fonts);
        boolean[] pixels = new boolean[WIDTH * HEIGHT];
        draw(pixels, 10, 20, A, false); draw(pixels, 16, 20, B, false);
        // Nearby arbitrary graphics must not become text.
        for (int y = 50; y < 58; ++y) for (int x = 100; x < 120; ++x) pixels[y * WIDTH + x] = true;
        pair(r, pixels, 10, 20, false);
        pixels[20 * WIDTH + 10] = !pixels[20 * WIDTH + 10];
        check(r.recognize(pixels, WIDTH, HEIGHT).isEmpty(), "Changed glyph must fall back; no stale overlay");
        pixels = new boolean[WIDTH * HEIGHT];
        check(r.recognize(pixels, WIDTH, HEIGHT).isEmpty(), "Cleared screen must clear overlays");
        draw(pixels, 30, 40, A, true); draw(pixels, 36, 40, B, true);
        pair(r, pixels, 30, 40, true);
        pixels = new boolean[WIDTH * HEIGHT];
        draw(pixels, 10, 30, A, false); draw(pixels, 16, 30, B, false);
        pair(r, pixels, 10, 30, false);
        pixels = new boolean[WIDTH * HEIGHT]; draw(pixels, 10, 20, A, false);
        check(r.recognize(pixels, WIDTH, HEIGHT).isEmpty(), "Isolated shapes outside Home must stay pixels");
        pixels = new boolean[WIDTH * HEIGHT];
        draw(pixels, 149, 20, A, false); draw(pixels, 155, 20, B, false);
        pair(r, pixels, 149, 20, false);
        pixels = new boolean[WIDTH * HEIGHT];
        draw(pixels, 10, 20, A, false); draw(pixels, 16, 20, B, false);
        List<SharpTextRecognizer.Cell> previous = r.recognize(pixels, WIDTH, HEIGHT);
        // A blinking cursor in B's trailing blank column destroys the word-run
        // match, but both actual letters must retain the same sharp rendering.
        for (int y = 20; y < 28; ++y) pixels[y * WIDTH + 21] = true;
        List<SharpTextRecognizer.Cell> stable = r.recognizeStable(pixels, WIDTH, HEIGHT, previous);
        check(stable.size() == 2, "Cursor-on frame must keep both unchanged letters sharp");
        for (int y = 20; y < 28; ++y) pixels[y * WIDTH + 21] = false;
        check(r.recognizeStable(pixels, WIDTH, HEIGHT, stable).size() == 2, "Cursor-off frame must stay sharp");
        // Losing neighbouring context must not downgrade a still-valid letter.
        draw(pixels, 10, 20, new int[8], false);
        stable = r.recognizeStable(pixels, WIDTH, HEIGHT, previous);
        check(stable.size() == 1 && stable.get(0).glyph.character == 'B', "Keep unchanged B; remove cleared A");
        draw(pixels, 16, 20, B, true);
        stable = r.recognizeStable(pixels, WIDTH, HEIGHT, stable);
        check(stable.size() == 1 && stable.get(0).inverse, "Selection inversion must update preserved text");
        pixels[22 * WIDTH + 17] = !pixels[22 * WIDTH + 17];
        check(r.recognizeStable(pixels, WIDTH, HEIGHT, stable).isEmpty(), "Changed ink must immediately lose its overlay");
        pixels = new boolean[WIDTH * HEIGHT];
        check(r.recognizeStable(pixels, WIDTH, HEIGHT, previous).isEmpty(), "No cached text after clearing");
        draw(pixels, 10, 20, A, false); draw(pixels, 16, 20, B, false);
        // A stray padding pixel is not a cursor and must invalidate that cell.
        pixels[20 * WIDTH + 21] = true;
        stable = r.recognizeStable(pixels, WIDTH, HEIGHT, previous);
        check(stable.size() == 1 && stable.get(0).glyph.character == 'A', "Do not preserve arbitrarily changed padding");
        // Reacquire a letter even when no cache exists and the two-column
        // cursor fills its trailing padding plus the next cell's first column.
        pixels = new boolean[WIDTH * HEIGHT];
        draw(pixels, 10, 20, A, false); draw(pixels, 16, 20, B, false);
        for (int y = 20; y < 28; ++y) { pixels[y * WIDTH + 21] = true; pixels[y * WIDTH + 22] = true; }
        pair(r, pixels, 10, 20, false);
        stable = r.recognizeStable(pixels, WIDTH, HEIGHT, java.util.Collections.emptyList());
        check(stable.size() == 2, "Reacquire text with cursor already on");
        pixels[22 * WIDTH + 17] = !pixels[22 * WIDTH + 17];
        check(r.recognizeStable(pixels, WIDTH, HEIGHT, stable).size() == 1, "Cursor masking must not hide changed letter ink");
        // Small inverse shapes need a real inverse background, rather than
        // merely matching the negative space of a larger normal symbol.
        byte[] smallFonts = new byte[3 * 256 * 12];
        int[][] shapes = {{28,34,62,34,34}, {60,34,60,34,60}};
        for (int i=0;i<2;++i) {
            int off = ('A'+i)*12; smallFonts[off]=6; smallFonts[off+1]=5;
            for(int y=0;y<5;++y) smallFonts[off+2+y]=(byte)(shapes[i][y]<<2);
        }
        SharpTextRecognizer small = new SharpTextRecognizer(smallFonts);
        pixels = new boolean[WIDTH*HEIGHT];
        draw(pixels,10,30,shapes[0],true); draw(pixels,16,30,shapes[1],true);
        check(small.recognize(pixels,WIDTH,HEIGHT).isEmpty(), "Reject inverse fragments without inverse background");
        for(int y=28;y<=36;++y) for(int x=8;x<=23;++x) pixels[y*WIDTH+x]=true;
        draw(pixels,10,30,shapes[0],true); draw(pixels,16,30,shapes[1],true);
        previous=small.recognize(pixels,WIDTH,HEIGHT);
        check(previous.size()==2, "Real small inverse selection remains sharp");
        pixels = new boolean[WIDTH*HEIGHT];
        draw(pixels,10,30,shapes[0],true); draw(pixels,16,30,shapes[1],true);
        check(small.recognizeStable(pixels,WIDTH,HEIGHT,previous).isEmpty(), "Cached inverse text also requires its background");
        System.out.println("Small inverse text: negative-space rejection, genuine selection and cache invalidation passed.");
        System.out.println("Stable text: cursor blinking, lost run context, inversion, edits and clearing passed.");
        System.out.println("Sharp text: normal/inverse text, graphics fallback, edits, clearing, scrolling, isolated shapes and display edge passed.");
    }
}
