import QtQuick

// Fast, lightly bouncing spring for press feedback and small nudges.
SpringAnimation {
    spring: Theme.springSnappy
    damping: Theme.dampingSnappy
    mass: Theme.springMass
    epsilon: 0.002
}
