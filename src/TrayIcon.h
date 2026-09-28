#pragma once

#include <QObject>
#include <QString>

// Kadron's icon in the Windows notification area, so closing the window can
// leave the app running. Native Shell_NotifyIcon rather than
// QSystemTrayIcon, which would pull in all of QtWidgets. No-op elsewhere.
class TrayIcon : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supported READ supported CONSTANT)
    Q_PROPERTY(bool visible READ visible WRITE setVisible NOTIFY visibleChanged)
    // Draw the right-click menu dark, to match the app theme.
    Q_PROPERTY(bool dark MEMBER m_dark)
public:
    explicit TrayIcon(QObject *parent = nullptr);
    ~TrayIcon() override;

    bool supported() const;
    bool visible() const { return m_visible; }
    void setVisible(bool visible);

    // A notification from the tray icon; clicking it counts as activated().
    Q_INVOKABLE void showMessage(const QString &title, const QString &text);

    // Called by the hidden window that receives the icon's messages.
    long long handleMessage(unsigned message, unsigned long long wParam, long long lParam);

signals:
    void visibleChanged();
    void activated();
    void quitRequested();

private:
    bool add();
    void remove();
    void showMenu();

    void *m_window = nullptr;
    void *m_icon = nullptr;
    unsigned m_taskbarCreated = 0;
    bool m_visible = false;
    bool m_added = false;
    bool m_dark = true;
};
