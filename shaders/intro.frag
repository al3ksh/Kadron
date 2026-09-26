#version 440
// Startup intro (design/intro/kadron-intro.html, ported): a trim in the range
// strip becomes the Kadron mark. Everything is a function of `t`, which a
// UniformAnimator drives on the render thread, so the intro stays smooth while
// the UI thread is busy loading the app.
//
// Work happens in design units on a 1920x1080 stage centred in the item.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;            // seconds into the intro
    float exitAmount;   // 0..1 fade to the window colour at the end
    float stageScale;   // item pixels per design unit
    vec2 itemSize;      // item size in pixels
    vec2 wordSize;      // wordmark texture size in design units
    float wordBaseline; // baseline offset inside the wordmark texture, design units
    float glyphAdvance; // digit cell width in design units (at 20 px)
    float glyphHeight;  // digit cell height in design units (at 20 px)
    vec4 bg;
    vec4 lane;
    vec4 laneEdge;
    vec4 ink;
    vec4 inkPlayed;
    vec4 muted;
    vec4 accent;
    vec4 accentInk;
    vec4 playhead;
    vec4 playheadInk;
    vec4 playheadWash;
};

layout(binding = 1) uniform sampler2D wordTex;   // "Kadron", white on transparent
layout(binding = 2) uniform sampler2D digitTex;  // "0123456789:." in equal cells

const float CX = 960.0;
const float CY = 540.0;
const float LANE_W = 1320.0;
const float LANE_H = 200.0;
const float LANE_L = CX - LANE_W / 2.0;
const float LANE_R = CX + LANE_W / 2.0;
const float BAR_FIRST = LANE_L + 24.0;
const float BAR_STEP = 11.0;
const float BAR_COUNT = 116.0;
const float S = 214.0 / 256.0;          // mark size in logo units (kadron-mark.svg)
const float STROKE = 24.0 * S;

float aa;   // one pixel in design units

// ---- timing ------------------------------------------------------------------
float span(float a, float b) { return clamp((t - a) / (b - a), 0.0, 1.0); }
float expoOut(float p) { return p >= 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * p); }
float expoInOut(float p) {
    if (p <= 0.0) return 0.0;
    if (p >= 1.0) return 1.0;
    return p < 0.5 ? pow(2.0, 20.0 * p - 10.0) / 2.0 : (2.0 - pow(2.0, -20.0 * p + 10.0)) / 2.0;
}
float cubicInOut(float p) { return p < 0.5 ? 4.0 * p * p * p : 1.0 - pow(-2.0 * p + 2.0, 3.0) / 2.0; }
float cubicOut(float p) { return 1.0 - pow(1.0 - p, 3.0); }
float spring(float p) {
    if (p <= 0.0) return 0.0;
    if (p >= 1.0) return 1.0;
    return 1.0 - exp(-6.5 * p) * cos(9.0 * p);
}

float lx(float u) { return CX + (u - 128.0) * S; }
float ly(float v) { return CY + (v - 128.0) * S; }

// ---- shapes --------------------------------------------------------------------
float sdBox(vec2 p, vec2 c, vec2 halfSize, float r) {
    r = min(r, min(halfSize.x, halfSize.y));
    vec2 q = abs(p - c) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}
float cover(float d) { return clamp(0.5 - d / aa, 0.0, 1.0); }

vec3 over(vec3 base, vec4 color, float alpha) { return mix(base, color.rgb, clamp(alpha, 0.0, 1.0)); }

// Rectangle from its left/top corner, like the canvas version.
float rectCover(vec2 p, float x, float y, float w, float h, float r) {
    if (w <= 0.0 || h <= 0.0) return 0.0;
    return cover(sdBox(p, vec2(x + w / 2.0, y + h / 2.0), vec2(w / 2.0, h / 2.0), r));
}

// ---- text from the digit atlas ----------------------------------------------------
// Glyphs: 0-9, 10 ':', 11 '.'. Labels read m:ss.s.
float glyphAt(float seconds, int index) {
    float tenths = floor(seconds * 10.0 + 0.5);
    float whole = floor(tenths / 10.0);
    float secs = mod(whole, 60.0);
    float mins = floor(whole / 60.0);
    if (index == 0) return mod(mins, 10.0);
    if (index == 1) return 10.0;
    if (index == 2) return floor(secs / 10.0);
    if (index == 3) return mod(secs, 10.0);
    if (index == 4) return 11.0;
    return mod(tenths, 10.0);
}

// Alpha of a time label centred on `centre` with glyphs `size` design px tall.
float timeLabel(vec2 p, vec2 centre, float seconds, float size) {
    float k = size / 20.0;
    float adv = glyphAdvance * k * 0.78;   // digits sit tighter than their cells
    float h = glyphHeight * k;
    vec2 origin = centre - vec2(adv * 3.0, h / 2.0);
    vec2 q = p - origin;
    if (q.x < 0.0 || q.y < 0.0 || q.x >= adv * 6.0 || q.y >= h) return 0.0;
    int index = int(floor(q.x / adv));
    float g = glyphAt(seconds, index);
    // Each slot shows the middle of its glyph's cell at full size.
    float local = 0.5 + (fract(q.x / adv) - 0.5) * 0.78;
    vec2 uv = vec2((g + local) / 12.0, q.y / h);
    return texture(digitTex, uv).a;
}

// Playhead line with its pin, as in qml/RangeStrip.qml.
vec3 drawPlayhead(vec3 col, vec2 p, float x, float top, float bottom, float seconds, float alpha) {
    if (alpha <= 0.0) return col;
    col = over(col, playhead, alpha * rectCover(p, x - 1.5, top, 3.0, bottom - top, 0.0));
    float py = bottom + 4.0;
    float pw = glyphAdvance * 0.95 * 0.78 * 6.0 + 26.0;
    float body = sdBox(p, vec2(x, py + 9.0 + 13.5), vec2(pw / 2.0, 13.5), 6.0);
    // The notch pointing up at the line.
    vec2 q = p - vec2(x, py);
    float notch = max(max(-q.y, q.y - 10.0), abs(q.x) * 9.0 / 8.0 - q.y);
    float d = min(body, notch * 0.7);
    col = over(col, playheadWash, alpha * cover(d));
    col = over(col, playhead, alpha * cover(abs(d) - 0.75));
    col = over(col, playheadInk, alpha * timeLabel(p, vec2(x, py + 9.0 + 14.0), seconds, 19.0));
    return col;
}

float barHash(float i) { return fract(sin(i * 91.3458 + 7.13) * 47453.5453); }

void main() {
    aa = 1.0 / stageScale;
    vec2 pixel = qt_TexCoord0 * itemSize;
    vec2 p = (pixel - itemSize / 2.0) / stageScale + vec2(CX, CY);

    // The hand-off shrinks the whole stage a touch while it fades.
    float exitP = cubicInOut(exitAmount);
    p = (p - vec2(CX, CY)) / (1.0 - 0.03 * exitP) + vec2(CX, CY);

    float handlesIn = spring(span(0.62, 1.08));
    float cut = expoInOut(span(1.04, 1.42));
    float fold = expoInOut(span(1.38, 1.78));
    float slide = expoInOut(span(1.78, 2.14));

    float laneHalfW = LANE_W / 2.0 * expoOut(span(0.0, 0.5));
    float halfH = mix(LANE_H / 2.0, 78.0 * S, cut);
    float top = CY - halfH, bottom = CY + halfH;

    float hl0 = mix(LANE_L + 8.0, CX - 250.0, handlesIn);
    float hr0 = mix(LANE_R - 8.0, CX + 250.0, handlesIn);
    float hl = mix(hl0, lx(66.0), cut);
    float hr = mix(hr0, lx(202.0), cut);

    vec3 col = bg.rgb;

    if (fold < 1.0) {
        // mapX(x) is affine: squeezes the kept range onto the handles.
        float k = (hr - hl) / max(1.0, hr0 - hl0);
        float m = (1.0 - cut) + cut * k;
        float b = cut * (hl - hl0 * k);
        float keepL = mix(CX - laneHalfW, hl0, cut);
        float keepR = mix(CX + laneHalfW, hr0, cut);
        float bodyL = keepL * m + b, bodyR = keepR * m + b;

        float laneD = sdBox(p, vec2((bodyL + bodyR) / 2.0, CY), vec2(max(0.0, (bodyR - bodyL) / 2.0), halfH), 14.0);
        float laneA = (1.0 - fold) * (bodyR > bodyL ? 1.0 : 0.0);
        col = over(col, lane, laneA * cover(laneD));
        col = over(col, laneEdge, laneA * cover(abs(laneD) - 0.75));

        float phX = mix(LANE_L + 60.0, CX + 90.0, cubicInOut(span(0.18, 1.02)));

        // Waveform: the nearest bars to this pixel, clipped to the lane.
        if (laneD < 1.0) {
            float source = (p.x - b) / m;
            float centre = floor((source - BAR_FIRST) / BAR_STEP + 0.5);
            for (int j = -1; j <= 1; ++j) {
                float i = centre + float(j);
                if (i < 0.0 || i >= BAR_COUNT) continue;
                float x = BAR_FIRST + i * BAR_STEP;
                float u = (x - LANE_L) / LANE_W;
                float phrase = 0.55 + 0.45 * sin(u * 9.5 + 0.6) * sin(u * 3.1 + 1.2);
                float amp = clamp(0.12 + 0.6 * abs(phrase) + 0.35 * pow(barHash(i), 2.2), 0.08, 1.0);
                float delay = 0.06 + abs(x - CX) / (LANE_W / 2.0) * 0.34;
                float grow = expoOut(span(delay, delay + 0.28));
                bool inside = x >= hl0 && x <= hr0;
                if (grow <= 0.0 || (!inside && cut >= 1.0)) continue;
                float hRatio = inside ? 1.0 - cut : clamp(1.0 - cut * 1.6, 0.0, 1.0);
                float bh = (LANE_H - 40.0) * amp * grow * hRatio;
                if (bh <= 0.5) continue;
                bool played = x <= phX;
                float a = played ? 0.92 : 0.42;
                if (!inside) a *= mix(1.0, 0.28, handlesIn);
                a *= (1.0 - fold) * (inside ? 1.0 - cut : 1.0);
                vec4 c = played && inside ? ink : played ? inkPlayed : muted;
                float bar = cover(sdBox(p, vec2(x * m + b, CY), vec2(2.75, bh / 2.0), 2.75));
                col = over(col, c, a * bar * cover(laneD));
            }
        }

        // Selected range: faint wash and accent edges between the handles.
        if (handlesIn > 0.0) {
            float a = (1.0 - fold) * clamp(handlesIn * 1.4, 0.0, 1.0) * (1.0 - cut * 0.6);
            col = over(col, accent, a * 0.07 * rectCover(p, hl, top, hr - hl, bottom - top, 0.0));
            col = over(col, accent, a * rectCover(p, hl, top, hr - hl, 3.0, 0.0));
            col = over(col, accent, a * rectCover(p, hl, bottom - 3.0, hr - hl, 3.0, 0.0));
        }

        float phAlpha = span(0.12, 0.3) * (1.0 - span(1.0, 1.18));
        col = drawPlayhead(col, p, phX, top - 8.0, bottom + 8.0, 14.2 * (phX - LANE_L) / LANE_W, phAlpha);

        // In and out times above the handles.
        float labels = clamp(handlesIn * 1.3, 0.0, 1.0) * (1.0 - span(1.02, 1.2));
        if (labels > 0.0) {
            col = over(col, accent, labels * timeLabel(p, vec2(hl, top - 29.0), 14.2 * (hl - LANE_L) / LANE_W, 20.0));
            col = over(col, accent, labels * timeLabel(p, vec2(hr, top - 29.0), 14.2 * (hr - LANE_L) / LANE_W, 20.0));
        }
    }

    // Lockup: mark on the left, wordmark to its right.
    float markW = 160.0 * S, gap = 54.0;
    float markLeft = CX - (markW + gap + wordSize.x) / 2.0;
    float dx = (markLeft - lx(54.0)) * slide;
    float wordX = markLeft + markW + gap;

    // Handles, folding into the mark.
    float handlesAlpha = span(0.5, 0.66);
    if (handlesAlpha > 0.0) {
        vec2 q = p - vec2(dx, 0.0);
        float width = mix(14.0, STROKE, cut);
        if (fold <= 0.0) {
            for (int side = 0; side < 2; ++side) {
                float x = side == 0 ? hl : hr;
                float hTop = top - 4.0, hBottom = bottom + 4.0;
                col = over(col, accent, handlesAlpha * rectCover(q, x - width / 2.0, hTop, width, hBottom - hTop, width / 2.4));
                float gripY = (hTop + hBottom) / 2.0;
                col = over(col, accentInk, handlesAlpha * (1.0 - cut) * rectCover(q, x - 1.5, gripY - 16.0, 3.0, 32.0, 1.5));
            }
        } else {
            float r = STROKE / 2.0;
            float y1 = mix(top - 4.0 + width / 2.0, ly(50.0), fold);
            float y2 = mix(bottom + 4.0 - width / 2.0, ly(206.0), fold);
            float arm = (170.0 - 66.0) * S * fold;
            float x0 = lx(66.0);
            float bracket = min(min(sdSegment(q, vec2(x0 + arm, y1), vec2(x0, y1)), sdSegment(q, vec2(x0, y1), vec2(x0, y2))),
                                sdSegment(q, vec2(x0, y2), vec2(x0 + arm, y2))) - r;
            vec4 bracketColor = mix(accent, ink, clamp(fold * 1.4, 0.0, 1.0));
            col = over(col, bracketColor, handlesAlpha * cover(bracket));
            float jx = mix(lx(202.0), lx(126.0), fold);
            float ey1 = mix(top - 4.0 + width / 2.0, ly(58.0), fold);
            float ey2 = mix(bottom + 4.0 - width / 2.0, ly(198.0), fold);
            float chevron = min(sdSegment(q, vec2(lx(202.0), ey1), vec2(jx, CY)), sdSegment(q, vec2(jx, CY), vec2(lx(202.0), ey2))) - r;
            col = over(col, accent, handlesAlpha * cover(chevron));
        }
    }

    // Wordmark, scrubbed into view by the playhead.
    if (t >= 2.04) {
        float reveal = cubicOut(span(2.12, 2.6));
        float edge = mix(wordX - 20.0, wordX + wordSize.x + 22.0, reveal);
        vec2 wordTopLeft = vec2(wordX, CY + 62.0 - wordBaseline);
        vec2 uv = (p - wordTopLeft) / wordSize;
        if (p.x < edge && uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0)
            col = over(col, ink, texture(wordTex, uv).a);
        float phAlpha = span(2.04, 2.14) * (1.0 - span(2.6, 2.74));
        col = drawPlayhead(col, p, edge, CY - 104.0, CY + 96.0, 0.8 * reveal, phAlpha);
    }

    col = mix(col, bg.rgb, exitP);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
