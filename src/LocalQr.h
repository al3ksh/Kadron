#pragma once

#include <QColor>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQuickImageProvider>
#include <QUrl>
#include <QVector>

// Live QR codes. qrencode (on this device) only computes the module matrix;
// Kadron draws it, so the preview updates as you type and exports use any
// colors, size, PNG or SVG.
class LocalQr final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)
    Q_PROPERTY(int modules READ modules NOTIFY changed)
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    explicit LocalQr(QObject *parent = nullptr);
    ~LocalQr() override;
    bool available() const;
    bool busy() const;
    QString stage() const;
    QString errorText() const;
    QUrl outputUrl() const;
    int modules() const;
    int revision() const;

    // Recomputes the matrix for this content and error-correction level (L, M, Q, H).
    Q_INVOKABLE void update(const QString &content, const QString &level);
    // Writes the current code as PNG or SVG (by file suffix). Never overwrites.
    Q_INVOKABLE bool save(const QUrl &destination, int size, const QColor &foreground, const QColor &background, int margin = 2);
    Q_INVOKABLE void cancel();

    QImage render(int size, const QColor &foreground, const QColor &background, int margin = 2) const;
    QString svg(const QColor &foreground, const QColor &background, int margin = 2) const;
    // Parses qrencode's `-t ASCII` output (two characters per module, '#' = dark).
    static QVector<QVector<bool>> parseAscii(const QByteArray &text);

signals:
    void changed();

private:
    void fail(const QString &message);

    QPointer<QProcess> m_process;
    QString m_qrencode;
    QString m_stage;
    QString m_errorText;
    QUrl m_outputUrl;
    QVector<QVector<bool>> m_matrix;
    int m_revision = 0;
};

// Serves the live preview as image://qr/<revision>?fg=RRGGBB&bg=RRGGBB&size=N
class QrImageProvider final : public QQuickImageProvider
{
public:
    explicit QrImageProvider(LocalQr *qr);
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QPointer<LocalQr> m_qr;
};
