LicenseQuizzes = LicenseQuizzes or {}

local QUESTIONS_PER_ATTEMPT = 8
local MIN_CORRECT_TO_PASS = 6

local QUESTION_POOLS = {
    [Enums.LicenseCategory.B] = {
        {
            question = "Zbliżasz się do skrzyżowania ze znakiem STOP. Co robisz?",
            answers = {
                "Zatrzymuję się całkowicie, nawet jeśli nie widzę innych pojazdów",
                "Zwalniam, ale nie muszę się zatrzymywać, jeśli droga jest pusta",
                "Zatrzymuję się tylko, gdy widzę inny pojazd",
            },
            correctIndex = 1,
        },
        {
            question = "Na skrzyżowaniu z czterema znakami STOP (all-way stop), kto ma pierwszeństwo?",
            answers = {
                "Pojazd, który zatrzymał się pierwszy",
                "Pojazd po prawej stronie, niezależnie od kolejności",
                "Zawsze pojazd jadący prosto",
            },
            correctIndex = 1,
        },
        {
            question = "Na skrzyżowaniu bez znaków ani sygnalizacji, kto ustępuje pierwszeństwa?",
            answers = {
                "Kierowca po lewej ustępuje kierowcy po prawej",
                "Kierowca po prawej zawsze ustępuje kierowcy po lewej",
                "Pierwszeństwo ma szybszy pojazd",
            },
            correctIndex = 1,
        },
        {
            question = "Jaki jest zazwyczaj limit prędkości w strefie szkolnej podczas godzin lekcyjnych?",
            answers = {
                "25 mph (ok. 40 km/h)",
                "45 mph (ok. 70 km/h)",
                "Brak limitu, jeśli nie widać dzieci",
            },
            correctIndex = 1,
        },
        {
            question = "Co oznacza 'zasada trzech sekund' (three-second rule)?",
            answers = {
                "Minimalny bezpieczny odstęp czasowy od pojazdu jadącego z przodu",
                "Czas na włączenie kierunkowskazu przed skrętem",
                "Czas oczekiwania na zielonym świetle przed ruszeniem",
            },
            correctIndex = 1,
        },
        {
            question = "Czy wyprzedzanie po prawej stronie jest kiedykolwiek dozwolone?",
            answers = {
                "Nigdy, jest zawsze nielegalne",
                "Tak, np. gdy pojazd z przodu skręca w lewo i jest wystarczająco miejsca",
                "Tylko w nocy",
            },
            correctIndex = 2,
        },
        {
            question = "Co oznacza żółte światło na sygnalizacji świetlnej?",
            answers = {
                "Przyspiesz, aby zdążyć przejechać",
                "Sygnalizacja zaraz zmieni się na czerwone - zatrzymaj się, jeśli możesz bezpiecznie",
                "Masz pierwszeństwo przed pojazdami na czerwonym",
            },
            correctIndex = 2,
        },
        {
            question = "Kiedy kierowca i pasażerowie muszą zapinać pasy bezpieczeństwa?",
            answers = {
                "Tylko na autostradzie",
                "Zawsze, gdy pojazd jest w ruchu",
                "Tylko kierowca musi, pasażerowie nie",
            },
            correctIndex = 2,
        },
        {
            question = "Jaki jest typowy dopuszczalny limit stężenia alkoholu we krwi (BAC) dla kierowców powyżej 21 roku życia?",
            answers = {
                "0.08%",
                "0.15%",
                "Brak limitu, liczy się tylko subiektywna trzeźwość",
            },
            correctIndex = 1,
        },
        {
            question = "Kiedy należy włączyć światła mijania?",
            answers = {
                "Tylko gdy pada deszcz",
                "Od zmierzchu do świtu oraz przy ograniczonej widoczności (deszcz, mgła)",
                "Tylko na drogach bez oświetlenia ulicznego",
            },
            correctIndex = 2,
        },
        {
            question = "Czy skręt w prawo na czerwonym świetle jest zazwyczaj dozwolony?",
            answers = {
                "Tak, po pełnym zatrzymaniu i upewnieniu się, że droga jest wolna, chyba że znak tego zabrania",
                "Nigdy, to zawsze nielegalne",
                "Tak, bez zatrzymywania się",
            },
            correctIndex = 1,
        },
        {
            question = "Pieszy wchodzi na oznakowane przejście dla pieszych. Co robi kierowca?",
            answers = {
                "Przyspiesza, aby przejechać przed pieszym",
                "Ustępuje pierwszeństwa pieszemu",
                "Trąbi, aby pieszy się cofnął",
            },
            correctIndex = 2,
        },
        {
            question = "Słyszysz syrenę pojazdu uprzywilejowanego (karetka/straż pożarna/policja) z tyłu. Co robisz?",
            answers = {
                "Zjeżdżasz do prawej krawędzi i zatrzymujesz się, jeśli to bezpieczne",
                "Przyspieszasz, aby zjechać mu z drogi jak najszybciej",
                "Ignorujesz, jeśli jedziesz zgodnie z limitem prędkości",
            },
            correctIndex = 1,
        },
        {
            question = "Jak blisko hydrantu przeciwpożarowego zazwyczaj nie wolno parkować?",
            answers = {
                "Ok. 3 metry (10 stóp)",
                "Ok. 30 centymetrów",
                "Parkowanie przy hydrancie jest zawsze dozwolone",
            },
            correctIndex = 1,
        },
        {
            question = "Czy pisanie SMS-ów podczas prowadzenia pojazdu jest legalne?",
            answers = {
                "Tak, jeśli jedziesz wolno",
                "Nie, jest zabronione w większości stanów",
                "Tak, ale tylko na czerwonym świetle",
            },
            correctIndex = 2,
        },
        {
            question = "Co to jest 'tailgating'?",
            answers = {
                "Jazda zbyt blisko za pojazdem z przodu",
                "Parkowanie równoległe",
                "Wyprzedzanie na podwójnej linii ciągłej",
            },
            correctIndex = 1,
        },
        {
            question = "Jaki jest typowy limit prędkości na drodze osiedlowej (residential area), o ile nie oznaczono inaczej?",
            answers = {
                "25 mph (ok. 40 km/h)",
                "60 mph (ok. 95 km/h)",
                "Brak limitu",
            },
            correctIndex = 1,
        },
        {
            question = "Czy zawracanie (U-turn) w pobliżu skrzyżowania jest zawsze dozwolone?",
            answers = {
                "Tak, w każdym miejscu",
                "Nie - jest zabronione tam, gdzie widoczny jest znak zakazu zawracania lub ogranicza widoczność",
                "Tylko w nocy",
            },
            correctIndex = 2,
        },
        {
            question = "Wjeżdżasz na autostradę pasem włączania (merge lane). Kto ma pierwszeństwo?",
            answers = {
                "Pojazdy już jadące na autostradzie - dostosuj prędkość i wjedź w bezpieczną lukę",
                "Zawsze pojazd wjeżdżający",
                "Pierwszeństwo ustala się trąbieniem",
            },
            correctIndex = 1,
        },
        {
            question = "Co oznacza pojedyncza ciągła żółta linia na środku jezdni?",
            answers = {
                "Wyprzedzanie dozwolone z obu stron",
                "Wyprzedzanie zabronione z Twojej strony",
                "To tylko oznaczenie dekoracyjne, nie ma znaczenia",
            },
            correctIndex = 2,
        },
        {
            question = "Twój pojazd zaczyna 'aquaplanować' (poślizg na wodzie). Co robisz?",
            answers = {
                "Gwałtownie hamujesz i skręcasz kierownicą",
                "Puszczasz gaz i trzymasz kierownicę prosto, delikatnie zwalniając",
                "Przyspieszasz, aby szybciej przejechać kałużę",
            },
            correctIndex = 2,
        },
    },
    -- [Enums.LicenseCategory.A] / [C] / [D] = nil - no quiz
}

function LicenseQuizzes.hasPool(category)
    return QUESTION_POOLS[category] ~= nil and #QUESTION_POOLS[category] > 0
end

function LicenseQuizzes.sample(category)
    local pool = QUESTION_POOLS[category]
    if not pool or #pool == 0 then
        return nil
    end

    local indexes = {}
    for i = 1, #pool do
        indexes[i] = i
    end

    local count = math.min(QUESTIONS_PER_ATTEMPT, #indexes)
    for i = 1, count do
        local swapWith = math.random(i, #indexes)
        indexes[i], indexes[swapWith] = indexes[swapWith], indexes[i]
    end

    local sampled = {}
    for i = 1, count do
        sampled[i] = indexes[i]
    end
    return sampled
end

function LicenseQuizzes.toClientQuestions(category, poolIndexes)
    local pool = QUESTION_POOLS[category]
    local questions = {}
    for i, poolIndex in ipairs(poolIndexes) do
        local entry = pool[poolIndex]
        questions[i] = { question = entry.question, answers = entry.answers }
    end
    return questions
end

function LicenseQuizzes.grade(category, poolIndexes, answerIndexes)
    local pool = QUESTION_POOLS[category]
    local correctCount = 0
    local totalCount = #poolIndexes

    for i, poolIndex in ipairs(poolIndexes) do
        local entry = pool[poolIndex]
        -- entry.correctIndex is 1-based (this file's own Lua array
        -- convention, matches how the answers table above is written),
        -- but answerIndexes[i] is 0-based (CEF's <For> index, sent as-is
        -- by LicenseExamDialog.tsx's own submitQuizAnswer - JS/TS array
        -- convention) - convert here, at the one place both meet, rather
        -- than changing either side's own natural indexing convention.
        if type(answerIndexes) == "table" and answerIndexes[i] == entry.correctIndex - 1 then
            correctCount = correctCount + 1
        end
    end

    return correctCount >= MIN_CORRECT_TO_PASS, correctCount, totalCount
end

--- DEBUG helper (kept at the user's explicit request) - used by
-- LicenseExamService.lua's own buildQuestionPushPayload to chat-print
-- the correct answer for whichever question is currently being sent.
-- @param category string
-- @param poolIndex number index into QUESTION_POOLS[category]
-- @return number|nil checkboxNumber (1-based, top-to-bottom - matches
--         what the player visually sees, i.e. entry.correctIndex as-is,
--         NOT the 0-based value LicenseQuizzes.grade actually compares
--         against), string|nil correctAnswerText
function LicenseQuizzes.debugCorrectAnswer(category, poolIndex)
    local pool = QUESTION_POOLS[category]
    if not pool then
        return nil, nil
    end
    local entry = pool[poolIndex]
    if not entry then
        return nil, nil
    end
    return entry.correctIndex, entry.answers[entry.correctIndex]
end
