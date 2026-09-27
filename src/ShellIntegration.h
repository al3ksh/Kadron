#pragma once

#include <QObject>
#include <QStringList>

// "Kadron" in Explorer's right-click menu for media, images and PDFs.
//
// Each supported extension gets a cascading verb under the current user's
// SystemFileAssociations, so nothing needs administrator rights and no file
// type association changes. Every action starts Kadron with
// `--tool=<tool> "<file>"`; a running Kadron picks them up (SingleInstance).
// On Windows 11 classic verbs sit under "Show more options".
class ShellIntegration final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool supported READ supported CONSTANT)

public:
    struct Action {
        QString key;
        QString label;
        QString tool;
    };
    struct Group {
        QStringList extensions;
        QList<Action> actions;
    };
    static QList<Group> groups();
    static QStringList tools();

    explicit ShellIntegration(QObject *parent = nullptr);
    bool enabled() const;
    void setEnabled(bool enabled);
    bool supported() const;

    // `executable` is the kadron.exe the menu should start.
    static bool install(const QString &executable);
    static void uninstall();
    static bool installed();

signals:
    void enabledChanged();
};
