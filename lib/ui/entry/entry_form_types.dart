/// Small UI-only vocabulary shared across the entry form's crew widgets and
/// its draft-[Flight] mapper (`flight_draft_mapper.dart`). None of these are
/// domain types — they're the *questions the form asks*, not the raw facts
/// those answers resolve to. See `docs/entry-form.md` §4 and
/// `lib/domain/model/pilot_capacity.dart`'s dartdoc for why the domain model
/// itself has no such enums.
library;

/// §4B: "What was the arrangement?" — the EASA dual/SPIC discriminator.
enum InstructorArrangement {
  receivingInstruction,
  inCommandObserving;

  String get label => switch (this) {
    InstructorArrangement.receivingInstruction => 'I was receiving instruction',
    InstructorArrangement.inCommandObserving =>
      'I was in command, instructor observing only',
  };
}

/// §4C: "Who was in command?"
enum CommandChoice {
  me,
  otherPilot;

  String get label => switch (this) {
    CommandChoice.me => 'Me',
    CommandChoice.otherPilot => 'Other pilot',
  };
}

/// §4C: "Who was flying?"
enum FlyingChoice {
  me,
  otherPilot,
  bothSplit;

  String get label => switch (this) {
    FlyingChoice.me => 'Me',
    FlyingChoice.otherPilot => 'Other',
    FlyingChoice.bothSplit => 'Both — split',
  };
}

/// The countersignature block's own choice — always present, never required
/// to save (§4B/§4C, §8).
enum SignChoice {
  now,
  defer;

  String get label => switch (this) {
    SignChoice.now => 'Sign now',
    SignChoice.defer => 'Defer',
  };
}

/// §4B purpose-of-flight options, in the order docs/entry-form.md lists them.
const List<String> flightPurposes = [
  'Training — general',
  'Skill test',
  'Proficiency check',
  'SEP/TMG revalidation refresher',
  'FAA flight review (§61.56)',
  'FAA IPC (§61.57(d))',
  'Instrument training toward a rating',
];

/// Purposes that force a remarks entry (§4B), and the note explaining why —
/// shown under the purpose picker and, when remarks are still empty, as a
/// warning under the remarks field.
const Map<String, String> flightPurposeNotes = {
  'SEP/TMG revalidation refresher':
      'Instructor name and signature are mandatory in remarks under '
      'AMC1 FCL.050. This entry also feeds the SEP revalidation rule.',
  'Skill test': 'Examiner number, result and a remarks entry are required.',
  'Proficiency check':
      'Examiner number, result, rating affected and a remarks entry are '
      'required.',
  'Instrument training toward a rating':
      'A remarks entry is mandatory under AMC1 FCL.050.',
};

/// Purposes administered by an examiner rather than an ordinary instructor —
/// drives whether the examiner-number/result/rating-affected fields show.
bool purposeHasExaminer(String? purpose) =>
    purpose == 'Skill test' || purpose == 'Proficiency check';
