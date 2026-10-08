#include "TextOverlay.h"

#include <QColor>
#include <QRegularExpression>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QSet>

TextOverlay TextOverlay::fromMap(const QVariantMap &map)
{
    TextOverlay text;
    text.text = map.value("text").toString().left(500);
    text.startMs = map.value("startMs").toLongLong();
    text.endMs = map.value("endMs").toLongLong();
    if (map.contains("size") && map.value("size").typeId() == QMetaType::QString) {
        const auto name = map.value("size").toString();
        text.size = name == "small" ? 0.045 : name == "large" ? 0.095 : 0.065;
    } else {
        text.size = map.value("size", text.size).toDouble();
    }
    if (map.contains("position")) {
        const auto position = map.value("position").toString();
        text.y = position == "top" ? 0.07 + text.size * 0.6 : position == "middle" ? 0.5 : 0.93 - text.size * 0.6;
    }
    text.x = map.value("x", text.x).toDouble();
    text.y = map.value("y", text.y).toDouble();
    text.color = map.value("color", text.color).toString();
    text.font = map.value("font", text.font).toString();
    text.style = map.value("style", text.style).toString();
    text.normalize();
    return text;
}

QVariantMap TextOverlay::toMap() const
{
    return {{"text", text}, {"startMs", startMs}, {"endMs", endMs}, {"lengthMs", qMax<qint64>(0, endMs - startMs)},
            {"x", x}, {"y", y}, {"size", size}, {"color", color}, {"font", font}, {"style", style}};
}

void TextOverlay::normalize()
{
    x = qBound(0.0, x, 1.0);
    y = qBound(0.0, y, 1.0);
    size = qBound(0.02, size, 0.25);
    const QColor parsed(color);
    color = parsed.isValid() ? parsed.name(QColor::HexRgb) : QStringLiteral("#ffffff");
    if (!fonts().contains(font))
        font = QStringLiteral("sans");
    if (!styles().contains(style))
        style = QStringLiteral("outline");
}

const QStringList &TextOverlay::fonts()
{
    static const QStringList names{"sans", "impact", "black", "serif", "mono"};
    return names;
}

const QStringList &TextOverlay::styles()
{
    static const QStringList names{"outline", "box", "shadow"};
    return names;
}

QString TextOverlay::fontFile(const QString &font)
{
    const auto folder = qEnvironmentVariable("WINDIR", QStringLiteral("C:/Windows")) + "/Fonts/";
    QStringList files;
    if (font == "impact") files << "impact.ttf";
    else if (font == "black") files << "ariblk.ttf";
    else if (font == "serif") files << "georgiab.ttf";
    else if (font == "mono") files << "consolab.ttf";
    files << "segoeuib.ttf" << "arialbd.ttf" << "arial.ttf";
    for (const auto &name : std::as_const(files)) {
        if (QFileInfo::exists(folder + name))
            return folder + name;
    }
    return {};
}

QString TextOverlay::filter(const QVector<TextOverlay> &texts, qint64 segmentStartMs, qint64 segmentLengthMs, int canvasHeight)
{
    const auto seconds = [](qint64 milliseconds) { return QString::number(milliseconds / 1000.0, 'f', 3); };
    const auto share = [](double value) { return QString::number(value, 'f', 4); };
    QString result;
    for (int i = 0; i < texts.size(); ++i) {
        const auto &text = texts.at(i);
        const auto start = text.startMs - segmentStartMs;
        const auto end = text.endMs - segmentStartMs;
        if (end <= 0 || start >= segmentLengthMs || end - start < 100)
            continue;
        const auto fontSize = qMax(8, qRound(canvasHeight * text.size));
        QString look;
        if (text.style == "box")
            look = QStringLiteral(":box=1:boxcolor=black@0.6:boxborderw=%1").arg(qMax(2, qRound(fontSize * 0.3)));
        else if (text.style == "shadow")
            look = QStringLiteral(":shadowx=%1:shadowy=%1:shadowcolor=black@0.7").arg(qMax(1, qRound(fontSize / 18.0)));
        else
            look = QStringLiteral(":borderw=%1:bordercolor=black@0.6").arg(qMax(1, qRound(fontSize / 16.0)));
        // A short fade at both ends, in sequence time so it carries across clips.
        const auto fade = seconds(qMin<qint64>(200, (end - start) / 2));
        result += QStringLiteral(",drawtext=fontfile=font_%1.ttf:textfile=text_%2.txt:expansion=none:text_align=center"
                                 ":fontsize=%3:fontcolor=0x%4%5"
                                 ":x='clip(w*%6-text_w/2,0,max(0,w-text_w))':y='clip(h*%7-text_h/2,0,max(0,h-text_h))'"
                                 ":alpha='clip(min((t-(%8))/%10,(%9-t)/%10),0,1)':enable='between(t,%8,%9)'")
                      .arg(text.font).arg(i).arg(fontSize).arg(text.color.mid(1), look, share(text.x), share(text.y))
                      .arg(seconds(start), seconds(end), fade);
    }
    return result;
}

bool TextOverlay::writeAssets(const QString &directory, const QVector<TextOverlay> &texts)
{
    // drawtext reads the text and the font from files, which spares escaping
    // the text and the font's path.
    QSet<QString> copied;
    for (int i = 0; i < texts.size(); ++i) {
        const auto &text = texts.at(i);
        if (!copied.contains(text.font)) {
            const auto source = fontFile(text.font);
            const auto target = directory + QStringLiteral("/font_%1.ttf").arg(text.font);
            if (source.isEmpty() || (!QFileInfo::exists(target) && !QFile::copy(source, target)))
                return false;
            copied.insert(text.font);
        }
        QSaveFile file(directory + QStringLiteral("/text_%1.txt").arg(i));
        if (!file.open(QIODevice::WriteOnly) || file.write(text.text.toUtf8()) < 0 || !file.commit())
            return false;
    }
    return true;
}

QVector<TextOverlay> TextOverlay::parseSubtitles(const QString &content)
{
    static const QRegularExpression timing(
        QStringLiteral(R"((?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3}))"));
    static const QRegularExpression tags(QStringLiteral(R"(<[^>]*>|\{\\[^}]*\})"));
    const auto milliseconds = [](const QRegularExpressionMatch &match, int first) {
        const auto fraction = match.captured(first + 3).leftJustified(3, '0');
        return ((match.captured(first).toLongLong() * 60 + match.captured(first + 1).toLongLong()) * 60
                + match.captured(first + 2).toLongLong()) * 1000 + fraction.toLongLong();
    };
    QVector<TextOverlay> result;
    auto text = content;
    text.remove(QChar(0xfeff));
    text.replace(QStringLiteral("\r\n"), QStringLiteral("\n")).replace('\r', '\n');
    const auto blocks = text.split(QRegularExpression(QStringLiteral(R"(\n\s*\n)")), Qt::SkipEmptyParts);
    for (const auto &block : blocks) {
        auto lines = block.split('\n');
        int timeLine = -1;
        QRegularExpressionMatch match;
        for (int i = 0; i < lines.size() && i < 3; ++i) {
            match = timing.match(lines.at(i));
            if (match.hasMatch()) {
                timeLine = i;
                break;
            }
        }
        if (timeLine < 0)
            continue;
        QStringList words;
        for (int i = timeLine + 1; i < lines.size(); ++i) {
            const auto line = QString(lines.at(i)).remove(tags).trimmed();
            if (!line.isEmpty())
                words << line;
        }
        TextOverlay overlay;
        overlay.text = words.join('\n').left(500);
        overlay.startMs = milliseconds(match, 1);
        overlay.endMs = milliseconds(match, 5);
        if (overlay.text.isEmpty() || overlay.endMs - overlay.startMs < 100)
            continue;
        overlay.size = 0.05;
        overlay.y = 0.9;
        overlay.style = QStringLiteral("box");
        result << overlay;
        if (result.size() >= 1000)
            break;
    }
    return result;
}

QString TextOverlay::toSrt(QVector<TextOverlay> texts)
{
    std::stable_sort(texts.begin(), texts.end(), [](const auto &a, const auto &b) { return a.startMs < b.startMs; });
    const auto time = [](qint64 ms) {
        ms = qMax<qint64>(0, ms);
        return QStringLiteral("%1:%2:%3,%4").arg(ms / 3600000, 2, 10, QChar('0')).arg(ms / 60000 % 60, 2, 10, QChar('0'))
            .arg(ms / 1000 % 60, 2, 10, QChar('0')).arg(ms % 1000, 3, 10, QChar('0'));
    };
    QString result;
    for (int i = 0; i < texts.size(); ++i) {
        const auto &text = texts.at(i);
        result += QStringLiteral("%1\n%2 --> %3\n%4\n\n").arg(i + 1).arg(time(text.startMs), time(text.endMs), text.text.trimmed());
    }
    return result;
}
