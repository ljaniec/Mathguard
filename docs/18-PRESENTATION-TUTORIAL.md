# Mathguard: przewodnik do prezentacji

Prezentacja: [PDF](../submission/Mathguard-HackYeah-2026.pdf) i [edytowalny PPTX](../submission/Mathguard-HackYeah-2026.pptx). Slajdy są po angielsku. Poniżej znajdziesz polskie objaśnienia, krótkie wypowiedzi po angielsku i scenariusz demonstracji. Ten sam skrót wypowiedzi jest w notatkach prezentera PPTX.

## Co właściwie zbudowaliśmy?

Mathguard to bramka między aplikacją a interakcjami z AI. Aplikacja może korzystać z modelu, narzędzia MCP lub innego agenta. Mathguard sprawdza każdą **zintegrowaną** interakcję i stosuje politykę przed wydaniem treści lub wykonaniem kontrolowanego efektu. Nie przechwytuje automatycznie ruchu, który aplikacja wysyła poza bramką.

Reguły wykrywają znane fakty, np. sekret, niedozwolone narzędzie lub przekroczony limit. Lokalny model ocenia znaczenie treści. Skompilowany worker Lean łączy wyniki. „Bezpieczne” od modelu nie usuwa zakazu reguły. Wynik może przepuścić treść, zmienić ją przez redakcję, skierować do zatwierdzenia albo zablokować.

Najkrótszy opis po angielsku:

> Mathguard applies live policy to AI interactions before content or tool effects leave the gateway. Deterministic rules and a local semantic model feed a compiled Lean decision kernel.

Nie trzeba tłumaczyć wszystkich nazw modułów ani czytać kodu ze slajdu. Najpierw pokaż problem i zachowanie systemu. Dowody oraz testy wyjaśnij jako uzasadnienie.

## Pięć minut: kolejność i czas

| Slajd | Główna myśl | Czas |
|---|---|---:|
| 1 | Kontrola przed wydaniem treści lub efektem | 20 s |
| 2 | Jedna wspólna ścieżka kontroli | 30 s |
| 3 | Model nie znosi twardego zakazu | 30 s |
| 4 | Polityka działa podczas prezentacji | 25 s |
| 5 | Ochrona danych i artefaktów | 25 s |
| 6 | Budżet przed wywołaniem | 25 s |
| 7 | Zgoda, trwałość i ponowienie | 25 s |
| 8 | Dashboard i krótki pokaz | 65 s |
| 9 | Zakres dowodów i testów | 30 s |
| 10 | Jak juror uruchamia projekt | 15 s |

To daje około 4 min 50 s. Jeśli masz trzy minuty, połącz 4–5 i 6–7 w krótkie wyjaśnienia, a w dashboardzie pokaż tylko blokadę sekretu oraz zmianę polityki. Zachowaj slajdy 3 i 9: wyjaśniają, co jest hybrydowe i co rzeczywiście potwierdziliśmy.

## 1. A control layer for AI

**Po polsku:** nie sprzedajemy nowego agenta. Dostarczamy warstwę, którą deweloper umieszcza przed modelem i narzędziami. Ona pilnuje zasad organizacji. W logo tarcza oznacza granicę, symbol ∀ oznacza wspólną regułę dla interakcji, a połączone węzły pokazują komunikację systemów.

**Powiedz:**

> Mathguard sits between an application and its AI interactions. It applies a live policy before releasing content or committing a tool effect. The model and the application stay under the developer’s control.

**Wskaż:** tytuł. Nie poświęcaj czasu na omawianie ornamentów logo, chyba że juror o nie zapyta.

**Przejście:** “Here is where that control happens.”

## 2. One shared enforcement path

**Po polsku:** aplikacja wywołuje HTTP gateway lub SDK. Sprawdzamy wejście i wyjście. To obejmuje prompty, odpowiedzi modeli, komunikację agentów, żądania i wyniki narzędzi oraz przyjęcie artefaktów. Dla dowolnego zewnętrznego narzędzia integrator musi użyć SDK i sam zapewnić poprawność jego efektów. Ledger jest naszym działającym przykładem efektu nieodwracalnego.

**Powiedz:**

> Applications use the gateway or SDK for prompts, model replies, tools, agent messages and artifacts. Rules and a local classifier produce facts. The compiled Lean worker decides admission and resource use. The dashboard receives sanitized audit metadata.

**Wskaż:** od aplikacji do Mathguard i celu. Następnie plik polityki od góry i raportowanie od dołu. Agent, właściciel i operator mają różne uprawnienia.

**Przejście:** “Both checks can add a restriction.”

## 3. AI cannot relax a hard denial

**Po polsku:** regex sam nie wystarcza, a model sam również nie wystarcza. Reguły i model mają różne zadania. Jeśli reguła dopasowała blokowaną sygnaturę, model nie może jej dopuścić. Jeśli reguła nie znalazła nic, model może nadal dostrzec atak pośredni. „Review” oznacza oczekiwanie, a nie wykonanie. Tryb strict blokuje brak poprawnej odpowiedzi modelu; balanced wymaga review; permissive może przepuścić z alertem zgodnie z polityką.

**Powiedz:**

> A deterministic denial always wins, even when the local model says safe. Semantic detection can add restrictions. The final result is pass, redact, review or block. Strict mode blocks when the classifier times out or returns malformed output.

**Wskaż:** pierwszy wiersz tabeli. To jest najprostszy przykład wymaganej hybrydowej obrony.

**Przejście:** “The organization can change these rules live.”

## 4. Live policy, safe reload

**Po polsku:** pokaż edycję prywatnej kopii polityki używanej przez uruchomiony gateway. Poprawny plik aktywuje nową wersję. Zły JSON nie usuwa starej ochrony. Jeśli nigdy nie było poprawnego pliku, wszystko jest blokowane. Odczyt, walidacja i rozmiar konfiguracji są ograniczone. Reload nie resetuje rachunków ani wykorzystanego budżetu.

**Powiedz:**

> The judges can edit the policy while the gateway is running. A valid edit activates. An invalid edit keeps the last valid version. With no valid policy, traffic is blocked. Reloading does not reset balances or consumed resources.

**Wskaż:** trzy wiersze, bez czytania długiego JSON. W demonstracji zmień tylko jeden parametr.

**Przejście:** “The policy also controls what content can leave.”

## 5. Checks before content escapes

**Po polsku:** sekrety blokujemy lub redagujemy zgodnie z polityką. Dane osobowe można redagować albo blokować. Testy obejmują również dane kodowane i podzielone, Unicode, treści polskie oraz instrukcje w wynikach narzędzi. To skończony zbiór testów, nie obietnica wykrycia każdego ataku. Artefakt musi mieć zatwierdzony hash i ograniczony, bezpiecznie analizowany format. Pickle nigdy nie jest wykonywany. Przyjęcie artefaktu nie jest dowodem bezpieczeństwa wszystkich wag lub bibliotek ładujących model.

**Powiedz:**

> We inspect incoming and outgoing content. Secrets are blocked or redacted by policy. Personal data can be redacted or blocked by policy. Artifact admission checks a pinned hash and bounded inert format structure. Pickle and executable formats are refused. Detection coverage is empirical.

**Wskaż:** kontrolę dla każdej kategorii. Szczegóły dekodowania zostaw na pytania.

**Przejście:** “Content safety is only one part of control.”

## 6. Budget before dispatch

**Po polsku:** rezerwacja zasobów poprzedza wywołanie. Tokeny, czas i liczba wywołań mają limity. W polityce istnieje też księgowa jednostka pieniężna, ale lokalny model nie oznacza rzeczywistej faktury od płatnego API. Dashboard odróżnia konserwatywnie naliczony limit od zaobserwowanych tokenów i czasu. Timeout zatrzymuje adapter, nie dowodzi zatrzymania GPU. Dlatego zachowujemy niepewną rezerwację i kwarantannę.

**Powiedz:**

> The gateway reserves a configured upper bound before calling a model. Budget and session limits stop further dispatch. Measured usage is reported separately. A timeout keeps the conservative charge and quarantines the provider until an operator verifies recovery.

**Wskaż:** “before dispatch”, potem zdanie o timeout. Dla modelowego czatu osobne etapy to semantyczna ocena wejścia, generacja i semantyczna ocena wyjścia. Każdy zużywa zasoby.

**Przejście:** “Irreversible effects need an additional boundary.”

## 7. Approval and safe retry

**Po polsku:** ledger to demonstrator finansowy z syntetycznymi kontami. Approval dotyczy dokładnego żądania, a nie dowolnego działania agenta. Sama zgoda nie wykonuje przelewu. Trwały dziennik pojedynczego procesu pozwala odtworzyć potwierdzony stan. Ponowienie dokładnego przelewu zwraca wcześniejsze potwierdzenie bez drugiego obciążenia. Niepewny zapis lub uszkodzenie stanu zamyka dostęp zamiast resetować budżet.

**Powiedz:**

> The ledger demonstrates an irreversible tool. Approval binds to the exact request. The durable single-node journal restores acknowledged state after restart. An exact retry returns the previous receipt without a second debit. External SDK effects still require their own idempotency protocol.

**Wskaż:** przejście od żądania przez właściciela do commit. Nie mów “every external tool is exactly once”.

**Przejście:** “An operator can see all of this.”

## 8. A clear operator view

**Po polsku:** tutaj przejdź do prawdziwego dashboardu. Pokaż wynik, aktywną politykę i zasoby. Dashboard pokazuje też tryb live lub fixture, stan dostawcy i kwarantannę. Treść promptów i tokeny nie trafiają do eksportu audytu. Token operatora wklejasz przed udostępnieniem ekranu; nie zapisuj go na slajdzie ani w nagraniu.

**Powiedz:**

> The dashboard shows decisions, resource headroom and security posture. Operators can see active versions, provider mode and quarantine. Audit and management exports contain sanitized metadata. Reserved bounds and observed model usage are displayed separately.

**Wskaż:** wynik ostatniego żądania, potem aktywne wersje i headroom. Nie omawiaj każdego pola. Korzystaj z [przewodnika dashboardu](16-DASHBOARD-GUIDE.md).

**Przejście:** “These behaviors have reproducible evidence.”

## 9. Evidence with a defined scope

**Po polsku:** Lean dowodzi właściwości modelu, np. że wynik semantyczny nie znosi twardej blokady. Runtime używa skompilowanego workera. Testy sprawdzają rzeczywiste połączenie parsera, gatewaya i workera. Liczba 156 oznacza wpisy katalogu audytu aksjomatów; nie 156 oddzielnych wymagań. Nowe gwarancje trwałości i granic HTTP są testowane. Ich pełniejsza formalizacja jest opisana w handoffie dla Aristotle.

**Powiedz:**

> We use Lean to prove how decisions combine and enforce constraints. The runtime suite exercises the compiled worker and hostile boundary inputs. The axiom report contains 156 catalog records. Detector accuracy and new persistence behavior are runtime evidence, with further proof work scoped for Aristotle.

**Wskaż:** dwa rodzaje dowodów. Jeśli ktoś pyta o “formal verification”, odpowiedz zakresem, nie samą dużą liczbą.

**Aktualna próba modelu:** Qwen2.5 1.5B przeszedł osiem przykładów development: trzy nieszkodliwe pytania, redakcję emaila i cztery ataki. Ten zbiór służył do opracowania promptu, więc nie jest niezależnym testem. Zachowaliśmy także błędy: 0.5B blokował nieszkodliwe pytania, a dodatkowa próba instrukcji ukrytej w notatce supportu była oczekiwaną blokadą, którą klasyfikator przepuścił. Nie przedstawiaj tych ośmiu przypadków jako skuteczności wobec dowolnych ataków.

**Przejście:** “The judges can reproduce the project locally.”

## 10. Local demonstration

**Po polsku:** `make setup` wybiera już zainstalowany lokalny model, wykonuje prawdziwy preflight i buduje pinned worker. Przy kilku modelach użyj `make setup MODEL=<dokładne ID>`. Potem `make run`. `make test` uruchamia testy. Pierwsza instalacja Lean, Mathlib i wag wymaga pobrania plików. Samo działanie nie wymaga płatnego API ani usług organizatora. W fixture mode zawsze informujemy, że wynik modelu jest podstawiony.

**Powiedz:**

> The judges can run three commands. Setup validates an installed local Ollama model and builds the pinned worker. Run starts the gateway. Test executes the automated checks. No paid API is required, and setup never silently substitutes fixture verdicts.

**Wskaż:** komendy. Nie wykonuj wielkiego pobrania wag na scenie. Szczegóły instalacji są w [quickstarcie](17-JUDGE-QUICKSTART.md).

## Próba przed wejściem na scenę

1. Na własnym komputerze zainstaluj Lean i Ollama zgodnie z [quickstartem](17-JUDGE-QUICKSTART.md). Użyj dokładnego ID lokalnego modelu. Ustaw `OLLAMA_NO_CLOUD=1` dla procesu Ollama i uruchom go ponownie. Wagi muszą być lokalnie dostępne.
2. W repo wykonaj `make setup MODEL=<dokładne ID>`, `make test`, następnie `make run`. Preflight nie może zamienić nieudanego modelu na fixture.
3. Otwórz adres dashboardu wypisany przez launcher. Wykonaj `make credentials` w prywatnym terminalu i zaloguj operatora oraz potrzebne role. Dopiero potem udostępnij ekran.
4. Zrób próbę bez internetu po pobraniu zależności. Sprawdź, czy model ma wystarczający czas na CPU danego laptopa. Nie zwiększaj limitów podczas demo bez wcześniejszego testu.
5. Zachowaj prywatny katalog runtime. Nie kasuj dziennika, żeby „naprawić” startup lub wyzerować limity. Osobny czysty katalog to osobne demo, z jawnie nowym stanem.

Przetestowany model to `qwen2.5:1.5b-instruct`. Domyślny limit odpowiedzi wynosi 128 tokenów, a deadline pojedynczego wywołania 15 sekund. Odpowiedzi celowo są krótkie. Klasyfikator korzysta ze ścisłego schematu JSON; host nadal sprawdza wynik i egzekwuje blokadę lub review. Sam poprawny JSON nie dowodzi poprawnej oceny zagrożenia.

Limit 128 tokenów jest wspólny dla klasyfikatora i generatora odpowiedzi. Dłuższa wypowiedź może skończyć się w połowie zdania. Poproś o krótką odpowiedź i uprzedź jurora: “The demo caps each stage at 128 output tokens, so longer answers can stop at the cap.” Dopuszczony czat wykonuje trzy wywołania lokalnego modelu. Jedna zmierzona próba na CPU zajęła około 4,26 s łącznie w tych etapach; na innym sprzęcie czas może być dłuższy, do trzech deadline’ów plus obsługa bramki. Powiedz: “We inspect both sides of generation, so an allowed chat makes three separately charged local calls.”

Świeża przykładowa polityka pozwala na **12 pełnych czatów**, zanim inne działania zużyją budżet. Limit 200 wywołań nie oznacza 200 czatów: każde zużywa trzy wywołania, a konserwatywny limit czasu kończy się wcześniej. To naliczone górne granice, nie faktyczny czas CPU. [Tabela polityki](../policies/README.md#budget-example) pokazuje obliczenie. Nowa sesja i restart nie zerują globalnych opłat.

Jeśli pokazujesz restart, zatrzymaj bramkę i uruchom `make run` z tym samym katalogiem runtime. Nie uruchamiaj ponownie setup i nie kasuj dziennika. Po udanym odświeżeniu dashboard wyczyści starą sesję, zgody i dane ponowienia; kliknij **Connect & create session**. Tokeny zostają w bieżącej karcie, a potwierdzone salda i naliczone zasoby wracają z SQLite. Niezatwierdzone żądanie i zgodę trzeba wydać od nowa. Powiedz: “Restart preserves committed state and charges, but invalidates live sessions and pending approvals. Reconnect explicitly; no action is retried automatically.”

## Krótki pokaz: trzy zachowania

| Krok | Co robisz | Co ma być widoczne |
|---|---|---|
| 1 | Wyślij nieszkodliwą interakcję, np. “Explain what a policy gateway does.” | Kontrolowana odpowiedź lub jawny review zależnie od prawdziwego modelu; licznik zasobów rośnie |
| 2 | Wyślij syntetyczny sekret, zakodowany w Base64 `password=DEMO_ONLY_SECRET_123`: `cGFzc3dvcmQ9REVNT19PTkxZX1NFQ1JFVF8xMjM=` | Block z powodem, bez przekazania sekretu do celu |
| 3 | Na działającym systemie zmień obsługę PII z redakcji na blokadę, zwiększając poprawnie wersję polityki | Nowa aktywna wersja i inny wynik tego samego syntetycznego adresu email |

Opcjonalnie w prywatnej kopii polityki wpisz chwilowo nieprawidłowy JSON, odśwież ją i pokaż zachowaną ostatnią poprawną wersję. Następnie od razu przywróć prawidłowy plik. Nie uszkadzaj repozytoryjnego sample ani dziennika.

Dla pokazu ledger otwórz jego sekcję w dashboardzie. Użyj kont syntetycznych. Najpierw pokaż, że wymagana zgoda nie zmienia salda. Wydaj ją jako właściciel, wykonaj dokładne żądanie i ponów je. Saldo nie powinno zmienić się drugi raz. Jeżeli ledger posiada już stan z poprzedniej próby, wyjaśnij to i sprawdź aktualne saldo przed rozpoczęciem.

## Jeśli coś nie działa podczas demonstracji

Pokaż faktyczny status. Timeout albo zła odpowiedź lokalnego modelu w strict mode ma blokować, a nie ukrywać awarię. Możesz wtedy pokazać twardą blokadę sekretu i bezpieczny reload. Jeśli uruchamiasz osobną próbę fixture, powiedz dokładnie:

> This is a labeled deterministic rehearsal with fixture verdicts. It demonstrates enforcement behavior, not local-model accuracy.

Nie przedstawiaj fixture jako działającego modelu. Nie usuwaj kwarantanny, zanim sprawdzisz model upstream. Nie kasuj stanu po awarii. Zautomatyzowane raporty są dowodem wcześniejszej próby, nie zastępują bieżącego statusu.

## Pytania jurorów

| Pytanie | Krótka odpowiedź |
|---|---|
| Dlaczego to hybrydowe? | Reguły i lokalny model tworzą niezależne ograniczenia. Model nie może odwołać twardego zakazu. |
| Co rzeczywiście udowodniliście? | Właściwości modeli Lean dotyczące decyzji, polityki, limitów i wybranych przejść. Granice Python/HTTP i trwałość mają testy oraz osobny plan formalizacji. |
| Czy wykryjecie każdy prompt injection? | Nie. Zestaw testów mierzy określone przykłady. Potrzebna jest niezależna ocena na nieznanych wcześniej promptach i dobranym modelu. |
| Co jeśli wpiszę tę pominiętą instrukcję z notatki supportu? | W rzeczywistej próbie wejście nadal dostało `risk=0`, ale generator odmówił pomocy. Bramka dopuściła tę bezpieczną odmowę. Osobno zablokowała przygotowaną szkodliwą odpowiedź. To dwa konkretne wyniki, nie dowód wykrycia każdej odmiany. |
| Czy działa bez płatnych API? | Tak. Wymagamy lokalnego Ollama i lokalnych wag. Nie ma zależności od OpenAI, Anthropic ani Copilot. |
| Co jeśli model lub gateway padnie? | Niepewne wywołanie zachowuje naliczone zasoby i kwarantannę. Trwały stan odtwarza potwierdzone przejścia. Niepewny dziennik zamyka dostęp. |
| Czy log jest odporny na administratora hosta? | Łańcuch hashy wykrywa niespójności. Bez zewnętrznej kotwicy nie dowodzi odporności na administratora, który przepisał cały plik lub przywrócił starszą poprawną kopię. |
| Czy to produkcyjny system rozproszony? | To demonstrator pojedynczego lokalnego węzła. Replikacja, twarde rozliczanie GPU i exactly-once efektów zewnętrznych wymagają osobnych protokołów. |
| Skąd koszty lokalnego modelu? | Mamy konfigurowalne jednostki księgowe oraz pomiary tokenów i czasu. Nie nazywamy tego rzeczywistym rachunkiem od usługodawcy. |
| Dlaczego budżet kończy się przed 200 czatami? | Czat zużywa trzy wywołania i trzy konserwatywne naliczenia. W świeżym sample limit compute pozwala na 12 pełnych czatów przed innym użyciem. Nowa sesja nie odnawia globalnego limitu. |
| Czy restart zgubi pieniądze lub zgody? | Potwierdzone salda i opłaty wracają z tego samego dziennika. Żywe sesje i oczekujące zgody są unieważniane. Dashboard prosi o jawne połączenie; nie ponawia działań automatycznie. |
| Co z formatami modeli? | Przyjęcie sprawdza przypięty hash i obsługiwany ograniczony format. Nie uruchamiamy pickle ani kodu. Bezpieczeństwo docelowego loadera jest oddzielną granicą. |
| Które kryteria priorytetyzowaliście? | Bezpieczeństwo 30%, architektura 20% i raportowanie 20% są wspólne dla obu dokumentów. Wszystkie cztery deliverables są w repo. Różnicę pozostałych wag zachowujemy w planie. |

Jeśli juror zapyta o znany pominięty prompt, powiedz po angielsku:

> The input classifier still missed this known prompt. In our live follow-up the proposer refused it, and the output gate allowed that refusal. A separate constructed harmful-output probe was blocked semantically. Those are two finite observations, not a guarantee that the second classifier catches every variant.

Pełna treść próby, odpowiedź i etapy dostawcy: [prelint-indirect-live.json](../evidence/prelint-indirect-live.json). Nie nazywaj bezpiecznej odmowy wynikiem blokady wejścia. `ALLOWED` oznacza tu dopuszczenie odpowiedzi odmawiającej, nie wykonanie instrukcji ani wyciek.

## Słownik dla prezentera

| Termin | Znaczenie |
|---|---|
| Gateway / control layer | Miejsce, przez które aplikacja kieruje kontrolowane interakcje |
| Deterministic control | Reguła dająca przewidywalny wynik na podstawie faktów |
| Semantic control | Lokalny model oceniający znaczenie i ryzyko treści |
| Kernel | Mały skompilowany fragment Lean, który podejmuje formalnie opisane decyzje |
| Redaction | Zastąpienie wykrytych danych przed ich wydaniem |
| Approval | Zgoda uprawnionego właściciela na konkretne żądanie |
| Fail closed | Brak pewności nie otwiera dostępu |
| Reservation | Zajęcie limitu przed wywołaniem, żeby równoległe żądania nie ominęły budżetu |
| Quarantine | Wstrzymanie nowych wywołań po niepewnym zdarzeniu |
| Exact retry | To samo zatwierdzone żądanie zwraca wcześniejszy wynik bez ponownego efektu |
| Fixture | Jawnie podstawiony wynik klasyfikatora do powtarzalnego testu |
| Axiom audit | Raport zależności dowodów od aksjomatów; nie licznik wykrytych ataków |

## Ostatnia aktualizacja dowodów — H1

Slajd z liczbą 156 nadal opisuje pierwotny katalog. Osobny audyt nowych wyników ma 85
pozycji. H1 dowodzi teraz zgodności rzeczywistej, typowanej gałęzi finansowej workera z
modelem przejścia, bez dodatkowego założenia o rozpoznawaniu `Json.null`. Powiedz:

> We now prove correspondence to the actual typed financial worker dispatch. The original
> 156-record catalog and the new 85-record audit are separate. Raw parsing, authentication
> and database crash behavior remain outside this proof.

Świeży pełny test przeszedł 189 przypadków wykonawczych, 14 statycznych i dziewięć prób
H1 na skompilowanym workerze. Dziesięć nowych prób z lokalnym modelem sprawdziło również
zgodę, ponowienie, zmianę polityki i restart. Starsze obrazy dashboardu zachowują wcześniejsze
identyfikatory workera. Po aktualizacji użyj osobnego prywatnego katalogu do nowego demo;
stary dziennik jest związany z poprzednim plikiem wykonywalnym i nie został zmigrowany.
[Wyniki i ograniczenia H1](verification/RELEASE-HARDENING-RESULTS.md).

Aktualne ograniczenia i mapa dowodów: [RELEASE-ASSURANCE.md](verification/RELEASE-ASSURANCE.md). Dalsze zadania Lean: [handoff Aristotle](../aristotle/FINAL-HARDENING-HANDOFF.md).
