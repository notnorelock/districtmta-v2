import { type Component, For, Show, createEffect, createSignal } from "solid-js";
import { GraduationCap, X } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Button } from "@/components/ui/Button";
import { Checkbox, CheckboxLabel } from "@/components/ui/Checkbox";
import { t } from "@/i18n";
import { licenseExamStore } from "@/stores/licenseExam.store";
import styles from "./LicenseExamDialog.module.scss";

function formatCooldown(totalSeconds: number): string {
  const minutes = Math.ceil(totalSeconds / 60);
  const key = minutes <= 1 ? "licenses.dialog.cooldownMinute" : "licenses.dialog.cooldownMinutes";
  return t()(key).replace("{count}", String(minutes));
}

function formatClock(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

/**
 * Marker-driven info + theory quiz dialog - opened/closed entirely by
 * server/client Lua via the "licenseExam" Overlay key (LicenseExamState.lua's
 * own LICENSE_EXAM_DIALOG_OPEN/_CLOSE handlers), same non-keybind pattern
 * VehicleStorageOverlay.tsx uses. Internal state machine driven purely by
 * licenseExamStore's own content signals (not a local "step" signal) -
 * quizQuestions() === null is the info screen, otherwise the quiz screen.
 * The quiz itself is step-by-step (one question at a time, server sends
 * the next one only after an answer is submitted) with a SINGLE shared
 * countdown for the whole quiz (not per-question) - see
 * LicenseExamService.lua's own pendingQuiz.deadlineTick comment. Passing
 * the quiz auto-starts the practical exam server-side (no extra step
 * here) - LicenseExamHud.tsx (a SEPARATE, always-mounted HUD card) takes
 * over visually once that begins.
 *
 * The pass/fail/timeout RESULT itself is intentionally never rendered in
 * this panel - the server closes the "licenseExam" Overlay the instant a
 * result lands (pass or fail, see LicenseExamService.lua's own
 * LICENSE_QUIZ_ANSWER/failQuiz), so there's no time for in-panel text to
 * be read before it unmounts. Feedback goes through the same native
 * NotificationService toast every other pass/fail moment in this exam
 * system already uses instead (LicenseExamService.lua's own
 * NotificationService.send calls) - licenseExamStore.quizResult still
 * exists as a signal, but this component doesn't consume it.
 */
export const LicenseExamDialog: Component = () => {
  const [selectedAnswer, setSelectedAnswer] = createSignal<number | null>(null);

  const info = licenseExamStore.dialogInfo;
  const questions = licenseExamStore.quizQuestions;
  const remainingSeconds = licenseExamStore.quizRemainingSeconds;

  // A fresh question arriving means the PREVIOUS selection no longer
  // applies - reset the local highlight so an old answer doesn't appear
  // pre-selected on the new question.
  createEffect(() => {
    questions();
    setSelectedAnswer(null);
  });

  function handleStart() {
    const category = info()?.category;
    if (!category) return;
    licenseExamStore.submitDialogStart(category);
  }

  function handleNext() {
    const q = questions();
    const answer = selectedAnswer();
    if (!q || answer === null) return;
    licenseExamStore.submitQuizAnswer(q.category, answer);
  }

  return (
    <Overlay name="licenseExam" transitionName="licenseExam">
      <div class={styles.root}>
        <div class={styles.panel}>
          <div class={styles.header}>
            <div class={styles.headerTitle}>
              <GraduationCap size={18} />
              <span class={styles.title}>{info()?.categoryName ?? t()("licenses.dialog.defaultTitle")}</span>
            </div>
            {/* Info screen only - no reason to make the player quit the
                marker's proximity just to back out of an unpaid attempt
                (e.g. while stuck on a cooldown). The quiz screen has no
                such button on purpose (see this component's own module
                comment) - once paid/started, backing out isn't offered here. */}
            <Show when={!questions()}>
              <button type="button" class={styles.closeButton} aria-label={t()("licenses.dialog.close")} onClick={() => licenseExamStore.dismissDialog()}>
                <X size={16} />
              </button>
            </Show>
          </div>

          <Show
            when={questions()}
            fallback={
              <div class={styles.body}>
                <p class={styles.description}>{t()("licenses.dialog.description")}</p>
                <div class={styles.feeRow}>
                  <span>{t()("licenses.dialog.fee")}</span>
                  <span class={styles.feeValue}>
                    {(info()?.fee ?? 0) > 0 ? `${info()?.fee} $` : t()("licenses.dialog.feeFree")}
                  </span>
                </div>
                <Show when={(info()?.cooldownRemainingSeconds ?? 0) > 0}>
                  <p class={styles.cooldown}>
                    {t()("licenses.dialog.cooldown").replace("{time}", formatCooldown(info()!.cooldownRemainingSeconds))}
                  </p>
                </Show>
                <Button
                  class={styles.startButton}
                  disabled={(info()?.cooldownRemainingSeconds ?? 0) > 0}
                  onClick={handleStart}
                >
                  {t()("licenses.dialog.start")}
                </Button>
              </div>
            }
          >
            {(q) => (
              <div class={styles.body}>
                <div class={styles.quizProgressRow}>
                  <span class={styles.quizProgress}>
                    {t()("licenses.dialog.questionProgress")
                      .replace("{current}", String(q().questionNumber))
                      .replace("{total}", String(q().totalQuestions))}
                  </span>
                  <span class={styles.quizClock}>{formatClock(remainingSeconds())}</span>
                </div>
                <div class={styles.question}>
                  <p class={styles.questionText}>{q().question.question}</p>
                  <div class={styles.answerList}>
                    <For each={q().question.answers}>
                      {(answer, answerIndex) => (
                        <Checkbox checked={selectedAnswer() === answerIndex()} onChange={() => setSelectedAnswer(answerIndex())}>
                          <CheckboxLabel>{answer}</CheckboxLabel>
                        </Checkbox>
                      )}
                    </For>
                  </div>
                </div>
                <Button class={styles.startButton} disabled={selectedAnswer() === null} onClick={handleNext}>
                  {t()("licenses.dialog.next")}
                </Button>
              </div>
            )}
          </Show>
        </div>
      </div>
    </Overlay>
  );
};
