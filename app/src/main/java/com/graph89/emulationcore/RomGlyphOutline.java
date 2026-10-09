package com.graph89.emulationcore;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Vector contours of the loaded ROM's bitmap, with its holes and disconnected
 * parts preserved. Coordinates use the original LCD pixel grid. */
public final class RomGlyphOutline {
    private static final class Edge {
        final int start, end, direction;
        boolean visited;
        Edge(int start, int end, int direction) {
            this.start = start; this.end = end; this.direction = direction;
        }
    }
    private static boolean ink(int[] rows, int width, int x, int y) {
        return x >= 0 && x < width && y >= 0 && y < rows.length
            && (rows[y] & (1 << (width - x - 1))) != 0;
    }
    private static void edge(List<Edge> edges, int[][] outgoing, int stride,
        int x0, int y0, int x1, int y1, int direction) {
        int start = y0 * stride + x0, end = y1 * stride + x1;
        outgoing[start][direction] = edges.size();
        edges.add(new Edge(start, end, direction));
    }
    /** Three unit edges alternating in the same horizontal/vertical direction
     * form a bitmap stair-step. Their edge midpoints form one straight diagonal. */
    public static boolean diagonalStep(float[] points, int corner) {
        int count = points.length / 2;
        for (int offset = -2; offset <= -1; ++offset) {
            int start = (corner + offset + count) % count;
            float[] dx = new float[3], dy = new float[3];
            boolean unit = true;
            for (int j = 0; j < 3; ++j) {
                int a = (start + j) % count, b = (a + 1) % count;
                dx[j] = points[b * 2] - points[a * 2];
                dy[j] = points[b * 2 + 1] - points[a * 2 + 1];
                unit &= Math.abs(dx[j]) + Math.abs(dy[j]) == 1;
            }
            if (unit && dx[0] == dx[2] && dy[0] == dy[2]
                && dx[0] * dx[1] + dy[0] * dy[1] == 0) return true;
        }
        return false;
    }
    public static List<float[]> trace(int[] rows, int width) {
        if (width < 1 || width > 8 || rows.length > 10) throw new IllegalArgumentException("Glyph dimensions");
        int stride = width + 1;
        int[][] outgoing = new int[stride * (rows.length + 1)][4];
        for (int[] point : outgoing) Arrays.fill(point, -1);
        List<Edge> edges = new ArrayList<Edge>();
        for (int y = 0; y < rows.length; ++y) for (int x = 0; x < width; ++x) {
            if (!ink(rows, width, x, y)) continue;
            if (!ink(rows, width, x, y - 1)) edge(edges, outgoing, stride, x, y, x + 1, y, 0);
            if (!ink(rows, width, x + 1, y)) edge(edges, outgoing, stride, x + 1, y, x + 1, y + 1, 1);
            if (!ink(rows, width, x, y + 1)) edge(edges, outgoing, stride, x + 1, y + 1, x, y + 1, 2);
            if (!ink(rows, width, x - 1, y)) edge(edges, outgoing, stride, x, y + 1, x, y, 3);
        }
        List<float[]> contours = new ArrayList<float[]>();
        for (int first = 0; first < edges.size(); ++first) {
            if (edges.get(first).visited) continue;
            List<Integer> vertices = new ArrayList<Integer>();
            int current = first;
            while (!edges.get(current).visited) {
                Edge e = edges.get(current); e.visited = true; vertices.add(e.start);
                int next = -1;
                // At diagonal pixel contact, turn left to join the foreground.
                // Ordinary outside corners turn right; hole contours run oppositely.
                int[] order = {(e.direction + 3) % 4, e.direction, (e.direction + 1) % 4, (e.direction + 2) % 4};
                for (int direction : order) {
                    int candidate = outgoing[e.end][direction];
                    if (candidate >= 0 && (!edges.get(candidate).visited || candidate == first)) { next = candidate; break; }
                }
                if (next < 0) throw new IllegalStateException("Open glyph contour");
                current = next;
            }
            List<Integer> corners = new ArrayList<Integer>();
            for (int i = 0; i < vertices.size(); ++i) {
                int p = vertices.get((i + vertices.size() - 1) % vertices.size());
                int c = vertices.get(i), n = vertices.get((i + 1) % vertices.size());
                int ax = c % stride - p % stride, ay = c / stride - p / stride;
                int bx = n % stride - c % stride, by = n / stride - c / stride;
                if (ax * by != ay * bx || ax * bx + ay * by <= 0) corners.add(c);
            }
            float[] points = new float[corners.size() * 2];
            for (int i = 0; i < corners.size(); ++i) {
                points[i * 2] = corners.get(i) % stride;
                points[i * 2 + 1] = corners.get(i) / stride;
            }
            contours.add(points);
        }
        return contours;
    }
}
