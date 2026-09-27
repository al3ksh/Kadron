#pragma once

#include <QLockFile>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QTimer>

class QLocalServer;
class QQuickWindow;

// One Kadron takes files from Explorer's menu, however many are selected.
//
// Explorer starts Kadron once per selected file. The first to start holds a
// lock and a local server; the others hand it their files and exit. Requests
// that arrive close together are delivered as one batch to Main.qml's
// openWith(tool, urls), so ten photos become one Images session.
class SingleInstance final : public QObject
{
    Q_OBJECT

public:
    struct Request {
        QString tool;
        QStringList files;
    };
    // `--tool=<tool>` plus file paths; without a tool, .kadr opens as a
    // project and anything else goes to the editor.
    static Request parse(const QStringList &arguments);

    explicit SingleInstance(QObject *parent = nullptr);
    ~SingleInstance() override;

    // True when this process should keep running as the receiving Kadron.
    bool claim();
    // Sends a request to the running Kadron; false if none answered.
    static bool forward(const Request &request);

    void take(const Request &request, bool raise);
    void attach(QQuickWindow *window);

private:
    void deliver();

    QLockFile m_lock;
    QLocalServer *m_server = nullptr;
    QPointer<QQuickWindow> m_window;
    QList<Request> m_pending;
    bool m_raise = false;
    QTimer m_batch;
};
