# Dock Multitouch Click Suppression Conflict

Blindly suppressing Quartz mouse clicks based on touch count (`touches.count >= 2`) kills physical trackpad press-clicks, because a user must touch the trackpad with two fingers to actuate a secondary click. Clicks must be filtered by pressure (`mouseEventPressure > 0`) and tightly scoped to active double-tap recognizer states rather than raw touch counts.
