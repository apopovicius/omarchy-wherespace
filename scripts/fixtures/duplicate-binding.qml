import QtQuick

// Deliberately broken: the lint check must flag the duplicate binding.
Item {
  width: 10
  width: 20
}
