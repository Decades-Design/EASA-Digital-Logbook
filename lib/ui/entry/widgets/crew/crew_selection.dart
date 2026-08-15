/// The four-way answer to "who else was on board?" — docs/entry-form.md §4.
/// `soleOccupant`, `carryingPassengers` and the occupant roles are derived
/// from this choice, never entered directly.
enum CrewSelection { justMe, withInstructor, withOtherPilot, withPassengers }
