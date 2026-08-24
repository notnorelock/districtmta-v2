import { createSignal } from "solid-js";
import type {
  LicenseExamStartedPayload,
  LicenseExamObjectiveUpdatedPayload,
  LicenseExamEndedPayload,
  LicenseExamDialogOpenPayload,
  LicenseQuizQuestionsPayload,
  LicenseQuizTickPayload,
  LicenseQuizResultPayload,
  LicenseCategory,
} from "@/types/licenseExam";
import { mta } from "@/lib/mta/MtaBridge";

// Plain signals, not a createStore - only one active exam per player at
// a time, same shape as group.store.ts's own duty slice.
const [active, setActive] = createSignal(false);
const [info, setInfo] = createSignal<LicenseExamStartedPayload | null>(null);
const [objective, setObjective] = createSignal("");
const [remainingMeters, setRemainingMeters] = createSignal<number | null>(null);
const [lastResult, setLastResult] = createSignal<LicenseExamEndedPayload | null>(null);

// Info + quiz dialog CONTENT slice - the dialog's own open/closed state
// is NOT tracked here, that's owned entirely by the "licenseExam"
// Overlay key (server/client Lua calling uiShowOverlay/uiHideOverlay,
// see Overlay.tsx's own module comment) - this store only holds what to
// render while it's visible. dialogInfo is set on open, quizQuestions is
// null until LICENSE_EXAM_DIALOG_START comes back, quizResult is null
// until a submit resolves.
const [dialogInfo, setDialogInfo] = createSignal<LicenseExamDialogOpenPayload | null>(null);
const [quizQuestions, setQuizQuestions] = createSignal<LicenseQuizQuestionsPayload | null>(null);
const [quizResult, setQuizResult] = createSignal<LicenseQuizResultPayload | null>(null);
// Fed purely by incoming pushes (the initial value on each question
// push, then licenses.quizTick's own once-a-second updates) - this
// store does no ticking of its own, exactly matching group.store.ts's
// own dutyTotalSeconds (the actual ticking happens in client Lua, see
// LicenseExamState.lua's own startQuizTicker, mirroring
// GroupDutyState.lua's identical duty-clock pattern).
const [quizRemainingSeconds, setQuizRemainingSeconds] = createSignal(0);

export const licenseExamStore = {
  active,
  info,
  objective,
  remainingMeters,
  lastResult,
  dialogInfo,
  quizQuestions,
  quizResult,
  quizRemainingSeconds,
  submitDialogStart(category: LicenseCategory) {
    mta.notify("licenses:examDialogStart", category);
  },
  submitQuizAnswer(category: LicenseCategory, answerIndex: number) {
    mta.notify("licenses:quizAnswer", category, answerIndex);
  },
  // "Zamknij" on the info screen only (see LicenseExamDialog.tsx's own
  // comment on why there's no close button on the quiz screen) - purely
  // client-side, no server round trip needed before the fee is paid.
  dismissDialog() {
    mta.notify("licenses:examDialogDismiss");
  },
};

mta.on("licenses.examStarted", (data) => {
  const payload = data as LicenseExamStartedPayload;
  setInfo(payload);
  setObjective(payload.objective);
  setRemainingMeters(null);
  setActive(true);
});

mta.on("licenses.examObjectiveUpdated", (data) => {
  const payload = data as LicenseExamObjectiveUpdatedPayload;
  setObjective(payload.objective);
  setRemainingMeters(payload.remainingMeters ?? null);
});

mta.on("licenses.examEnded", (data) => {
  setLastResult(data as LicenseExamEndedPayload);
  setActive(false);
  setInfo(null);
});

mta.on("licenses.examDialogOpen", (data) => {
  setDialogInfo(data as LicenseExamDialogOpenPayload);
  setQuizQuestions(null);
  setQuizResult(null);
});

mta.on("licenses.quizQuestionsReceived", (data) => {
  const payload = data as LicenseQuizQuestionsPayload;
  setQuizQuestions(payload);
  setQuizResult(null);
  setQuizRemainingSeconds(payload.remainingSeconds);
});

mta.on("licenses.quizTick", (data) => {
  setQuizRemainingSeconds((data as LicenseQuizTickPayload).remainingSeconds);
});

mta.on("licenses.quizResult", (data) => {
  setQuizResult(data as LicenseQuizResultPayload);
  // No client-side "close" bookkeeping needed here - the server always
  // follows up with its own LICENSE_EXAM_DIALOG_CLOSE either way (pass,
  // ordinary fail, or timeout - see LicenseExamService.lua's own
  // LICENSE_QUIZ_ANSWER/failQuiz), which hides the "licenseExam" Overlay
  // itself (uiHideOverlay - Overlay.tsx reacts to that alone, not this
  // store). The result is surfaced to the player via a native
  // NotificationService toast instead (LicenseExamService.lua's own
  // NotificationService.send calls) - LicenseExamDialog.tsx doesn't
  // render this signal, it exists only in case a future consumer needs it.
});

