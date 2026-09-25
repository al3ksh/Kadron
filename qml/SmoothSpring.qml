import QtQuick

// Settling spring for indicators, panels and anything that travels a distance.
SpringAnimation {
    spring: Theme.springSmooth
    damping: Theme.dampingSmooth
    mass: Theme.springMass
    epsilon: 0.25
}
