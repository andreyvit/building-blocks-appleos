# Rulebook for iOS, watchOS, tvOS & macOS Apps

Here's how apps should be written.


## Indentation

* ✅ MUST use 4 spaces for indentation
* ❌ don't use tabs


## Events & Notifications

Choices:

* ❌ MUST NOT use NotificationCenter wrappers like `SwiftEventBus`
* ❌ MUST NOT use key-value observing (KVO), unless interacting with a system framework with KVO-based API

Declaring notifications:

* ✅ MUST define notifications via `Notification.Name`
* ✅ SHOULD follow this pattern: `static let somethingHappened = Notification.Name("ClassName.somethingHappened")`

Sending:

* ✅ MUST send all notifications via NotificationCenter
* ✅ MUST send all notifications on the main queue, unless a particular component entirely runs on a background queue

Listening:

* TODO
