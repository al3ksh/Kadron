#include <QMetaMethod>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

class UiTests final : public QObject
{
    Q_OBJECT

private slots:
    void timelineInteractions();
};

void UiTests::timelineInteractions()
{
    QQmlEngine engine;
    QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(KADRON_SOURCE_DIR) + "/qml/Timeline.qml"));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    std::unique_ptr<QObject> object(component.create());
    auto *timeline = qobject_cast<QQuickItem *>(object.get());
    QVERIFY(timeline);
    timeline->setWidth(800);
    timeline->setHeight(146);
    timeline->setProperty("durationMs", 10000);
    timeline->setProperty("inMs", 2000);
    timeline->setProperty("outMs", 8000);
    timeline->setProperty("playheadMs", 2000);

    QQuickWindow window;
    window.setGeometry(50, 50, 800, 146);
    timeline->setParentItem(window.contentItem());
    window.show();
    QTest::qWait(100);

    const auto signal = [timeline](const char *name) {
        const auto index = timeline->metaObject()->indexOfSignal(name);
        return index < 0 ? QMetaMethod() : timeline->metaObject()->method(index);
    };
    const auto seekMethod = signal("seekRequested(double)");
    const auto inMethod = signal("inRequested(double)");
    const auto moveMethod = signal("moveRequested(double)");
    QVERIFY(seekMethod.isValid());
    QVERIFY(inMethod.isValid());
    QVERIFY(moveMethod.isValid());
    QSignalSpy seekSpy(timeline, seekMethod);
    QSignalSpy inSpy(timeline, inMethod);
    QSignalSpy moveSpy(timeline, moveMethod);

    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(400, 16));
    QVERIFY(seekSpy.count() > 0);
    QVERIFY(qAbs(seekSpy.last().first().toDouble() - 5000.0) < 100);

    seekSpy.clear();
    QTest::mouseClick(&window, Qt::LeftButton, {}, QPoint(300, 90));
    QVERIFY(seekSpy.count() > 0);

    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(160, 90));
    QTest::mouseMove(&window, QPoint(210, 90));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(210, 90));
    QVERIFY(inSpy.count() > 0);

    QTest::mousePress(&window, Qt::LeftButton, {}, QPoint(400, 92));
    QTest::mouseMove(&window, QPoint(450, 92));
    QTest::mouseRelease(&window, Qt::LeftButton, {}, QPoint(450, 92));
    QVERIFY(moveSpy.count() > 0);
}

QTEST_MAIN(UiTests)
#include "ui_tests.moc"
