import com.graph89.emulationcore.RomGlyphOutline;
import java.util.List;

/** Font identity and topology checks without a bundled ROM or Android runtime. */
public final class RomGlyphOutlineTest {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static boolean contains(List<float[]> contours, float x, float y) {
        boolean inside = false;
        for (float[] p : contours) {
            int n = p.length / 2;
            for (int i = 0, j = n - 1; i < n; j = i++) {
                float xi = p[2 * i], yi = p[2 * i + 1], xj = p[2 * j], yj = p[2 * j + 1];
                if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
            }
        }
        return inside;
    }
    private static List<float[]> verify(int[] rows, int width) {
        List<float[]> contours = RomGlyphOutline.trace(rows, width);
        float area = 0; int ink = 0;
        for (int row : rows) ink += Integer.bitCount(row);
        for (float[] p : contours) {
            int n = p.length / 2;
            check(n >= 4, "Closed contour must retain corners");
            for (int i = 0; i < n; ++i) {
                int j = (i + 1) % n;
                area += (p[i * 2] * p[j * 2 + 1] - p[j * 2] * p[i * 2 + 1]) / 2;
            }
        }
        check(Math.abs(area - ink) < .001, "Outline must preserve ROM ink area and hole orientation");
        for (int y = 0; y < rows.length; ++y) for (int x = 0; x < width; ++x) {
            boolean expected = (rows[y] & (1 << (width - x - 1))) != 0;
            check(contains(contours, x + .5f, y + .5f) == expected, "Outline changed a pixel center");
        }
        return contours;
    }
    public static void main(String[] args) {
        // A dot, shoulder, stem and three-pixel lower serif are distinct features.
        int[] i = {8, 0, 24, 8, 8, 8, 28, 0};
        List<float[]> contours = verify(i, 6);
        check(contours.size() == 2, "Lowercase i must retain its detached dot");
        check(contains(contours, 1.5f, 6.5f) && contains(contours, 3.5f, 6.5f), "Lowercase i must retain both serif ends");
        contours = verify(new int[] {31, 17, 17, 17, 31}, 5);
        check(contours.size() == 2 && !contains(contours, 2.5f, 2.5f), "Letter counter must remain open");
        check(verify(new int[] {2, 1}, 2).size() == 1, "Diagonal stroke must stay connected");
        verify(new int[] {31, 4, 4, 4, 4}, 5);
        verify(new int[] {7, 7, 7}, 3);
        check(verify(new int[] {0, 0}, 2).isEmpty(), "Blank glyph has no outline");
        // Exhaust every 3x3 glyph, including holes and ambiguous diagonal joins.
        for (int bitmap = 0; bitmap < 512; ++bitmap)
            verify(new int[] {(bitmap >> 6) & 7, (bitmap >> 3) & 7, bitmap & 7}, 3);
        System.out.println("ROM outlines: serif, detached dot, holes, diagonal strokes, blank glyph and all 512 3x3 patterns passed.");
    }
}
