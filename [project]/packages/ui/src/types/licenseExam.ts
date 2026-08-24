export type LicenseCategory = "A" | "B" | "C" | "D";

export interface LicenseExamStartedPayload {
  category: LicenseCategory;
  categoryName: string;
  objective: string;
}

export interface LicenseExamObjectiveUpdatedPayload {
  objective: string;
  // Present only during the free-driving finish segment.
  remainingMeters?: number;
}

export interface LicenseExamEndedPayload {
  result: "passed" | "failed";
  reason?: string;
}

export interface LicenseExamDialogOpenPayload {
  category: LicenseCategory;
  categoryName: string;
  fee: number;
  // 0 = no cooldown, "Rozpocznij" is enabled.
  cooldownRemainingSeconds: number;
}

export interface LicenseQuizQuestion {
  question: string;
  answers: string[];
}

// One question at a time (step-by-step quiz, not a batch) - a single
// shared clock for the WHOLE quiz, not per-question (see
// LicenseExamService.lua's own pendingQuiz.deadlineTick comment).
// remainingSeconds is the server's own authoritative value at push
// time; LicenseExamState.lua's local ticker (licenses.quizTick pushes)
// smooths it between real question pushes.
export interface LicenseQuizQuestionsPayload {
  category: LicenseCategory;
  questionNumber: number; // 1-based
  totalQuestions: number;
  question: LicenseQuizQuestion;
  remainingSeconds: number;
}

export interface LicenseQuizTickPayload {
  remainingSeconds: number;
}

export interface LicenseQuizResultPayload {
  passed: boolean;
  correctCount?: number;
  totalCount?: number;
  // Set when the shared quiz clock ran out (fails the whole quiz,
  // distinct from an ordinary wrong-answers fail) - see
  // LicenseExamService.lua's own failQuiz.
  timedOut?: boolean;
}
