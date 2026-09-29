#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

// Text burned into a video: what it says, when it shows and how it looks.
// x and y place the text's centre as a share of the frame, size is the
// font height as a share of the frame's height.
struct TextOverlay {
    QString text;
    qint64 startMs = 0;
    qint64 endMs = 0;
    double x = 0.5;
    double y = 0.85;
    double size = 0.065;
    QString color = QStringLiteral("#ffffff");
    QString font = QStringLiteral("sans");
    QString style = QStringLiteral("outline");

    // Reads a stored or QML map; older captions with a position and a size
    // name ("top", "large") land where they used to be.
    static TextOverlay fromMap(const QVariantMap &map);
    QVariantMap toMap() const;
    // Clamps every value into its range and drops unknown names.
    void normalize();

    static const QStringList &fonts();
    static const QStringList &styles();
    // The font file on this system for a font name, or an empty string.
    static QString fontFile(const QString &font);

    // drawtext filters (each led by a comma) for the texts over a stretch that
    // starts at segmentStartMs; text i reads text_<i>.txt and its font
    // font_<name>.ttf from the working directory (see writeAssets).
    static QString filter(const QVector<TextOverlay> &texts, qint64 segmentStartMs, qint64 segmentLengthMs, int canvasHeight);
    // Writes the text and font files filter() reads into directory.
    static bool writeAssets(const QString &directory, const QVector<TextOverlay> &texts);
};
