#pragma once

#include <QFutureWatcher>
#include <QPointer>
#include <QTemporaryDir>
#include <memory>
#include <QObject>
#include <QProcess>
#include <QUrl>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>
#include <atomic>

class LocalPdfTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool qpdfAvailable READ qpdfAvailable CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)
    Q_PROPERTY(qint64 outputBytes READ outputBytes NOTIFY changed)
    Q_PROPERTY(bool pagesAvailable READ pagesAvailable CONSTANT)
    Q_PROPERTY(bool loadingPages READ loadingPages NOTIFY pagesChanged)
    Q_PROPERTY(QUrl pagesDocument READ pagesDocument NOTIFY pagesChanged)
    Q_PROPERTY(QStringList pageImages READ pageImages NOTIFY pagesChanged)
    Q_PROPERTY(QString pagesError READ pagesError NOTIFY pagesChanged)
    // First page and page count per document for the Merge cards, keyed by
    // file URL string: {image: url, pages: int, error: string}.
    Q_PROPERTY(QVariantMap covers READ covers NOTIFY coversChanged)

public:
    explicit LocalPdfTools(QObject *parent = nullptr);
    ~LocalPdfTools() override;
    bool qpdfAvailable() const;
    bool busy() const;
    QString stage() const;
    QString errorText() const;
    QUrl outputUrl() const;
    qint64 outputBytes() const;
    bool pagesAvailable() const;
    bool loadingPages() const;
    QUrl pagesDocument() const;
    QStringList pageImages() const;
    QString pagesError() const;
    QVariantMap covers() const;

    // Renders every page of a PDF as a thumbnail for the visual editor.
    Q_INVOKABLE void loadPages(const QUrl &document);
    Q_INVOKABLE void clearPages();
    // Renders the first page of each document that has no cover yet.
    Q_INVOKABLE void loadCovers(const QVariantList &documents);
    // Page ranges like "1-3, 7" from a sorted list of 1-based pages.
    Q_INVOKABLE static QString pagesToRange(const QVariantList &pages);
    Q_INVOKABLE static QVariantList rangeToPages(const QString &range, int pageCount);
    // Renders one page large for the preview; emits pagePreviewReady.
    Q_INVOKABLE void renderPreview(int page);
    // Writes a new PDF from the loaded document: `pages` is an ordered list of
    // {page: 1-based source page, rotation: extra clockwise degrees}. Pages left
    // out are removed.
    Q_INVOKABLE bool compose(const QVariantList &pages, const QUrl &destination);
    static QStringList composeArguments(const QString &source, const QVariantList &pages, const QString &output);
    Q_INVOKABLE bool process(const QString &action, const QVariantList &files, const QString &pages,
                             int rotation, const QUrl &destination);
    Q_INVOKABLE void cancel();

signals:
    void changed();
    void pagesChanged();
    void coversChanged();
    void pagePreviewReady(int page, const QUrl &image);

private:
    void fail(const QString &message);
    void finish();

    QProcess m_process;
    QFutureWatcher<QString> m_writer;
    std::atomic_bool m_cancelled = false;
    QString m_qpdf;
    QString m_destination;
    QString m_partial;
    QString m_stage;
    QString m_errorText;
    QByteArray m_errorBuffer;
    QUrl m_outputUrl;
    qint64 m_outputBytes = 0;
    bool m_busy = false;
    QString m_pdftoppm;
    std::unique_ptr<QTemporaryDir> m_pagesDir;
    QPointer<QProcess> m_renderer;
    QUrl m_pagesDocument;
    QStringList m_pageImages;
    QString m_pagesError;
    int m_pagesGeneration = 0;
    std::unique_ptr<QTemporaryDir> m_coversDir;
    QVariantMap m_covers;
    QSet<QString> m_coversPending;
};
