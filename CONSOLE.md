12.6.0 - [FirebaseAnalytics][I-ACS023007] Analytics v.12.6.0 started
12.6.0 - [FirebaseAnalytics][I-ACS023008] To enable debug logging set the following application argument: -FIRAnalyticsDebugEnabled (see http://goo.gl/RfcP7r)
12.6.0 - [FirebaseAnalytics][I-ACS044003] GoogleAppMeasurementIdentitySupport dependency is not currently linked. IDFA will not be accessible.
12.6.0 - [FirebaseAnalytics][I-ACS800023] No pending snapshot to activate. SDK name: app_measurement
[SYNC] 📱 Initial connection state: Connected
12.6.0 - [FirebaseAnalytics][I-ACS023309] Failed to initiate on-device conversion measurement for retrieving aggregate first-party data. Linked on-device conversion measurement dependency does not support this feature.
12.6.0 - [FirebaseAnalytics][I-ACS023012] Analytics collection enabled
12.6.0 - [FirebaseAnalytics][I-ACS023220] Analytics screen reporting is enabled. Call Analytics.logEvent(AnalyticsEventScreenView, parameters: [...]) to log a screen view event. To disable automatic screen reporting, set the flag FirebaseAutomaticScreenReportingEnabled to NO (boolean) in the Info.plist
[APP_LAUNCH] 🏥 Performing data health check before app launch sync...
[APP_LAUNCH] ✅ User authenticated with ID: 1748465394255x432584139041047400
[DATA_HEALTH] 🏥 Performing comprehensive health check...
[DATA_HEALTH] ✅ User ID exists: 1748465394255x432584139041047400
[DATA_HEALTH] ✅ Current user exists: Jackson Sweet
[DATA_HEALTH] ✅ Company ID exists: 1748465773440x642579687246238300
[DATA_HEALTH] ✅ Company data exists
[DATA_HEALTH] ✅ SyncManager initialized
[DATA_HEALTH] ✅ ModelContext available
[DATA_HEALTH] ✅ All health checks passed - data is healthy
[APP_LAUNCH] ✅ Data health check passed
[APP_LAUNCH] 🔄 Proceeding with full sync and subscription check
[APP_LAUNCH_SYNC] 🚀 Starting app launch sync
[APP_LAUNCH_SYNC] - isConnected: true
[APP_LAUNCH_SYNC] - isAuthenticated: true
[APP_LAUNCH_SYNC] - currentUser: Jackson Sweet
[APP_LAUNCH_SYNC] - syncManager: available
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] 📊 Company Date Fields:
[SUBSCRIPTION]    - trialStartDate: nil
[SUBSCRIPTION]    - trialEndDate: nil
[SUBSCRIPTION]    - seatGraceStartDate: nil
[SUBSCRIPTION]    - subscriptionEnd: nil
[SUBSCRIPTION]    - subscriptionStatus: active
[SUBSCRIPTION]    - subscriptionPlan: business
[SUBSCRIPTION]    - maxSeats: 10
[SUBSCRIPTION]    - seatedEmployeeIds: 8 employees
[APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[SUBSCRIPTION] 📊 Computed Days Remaining:
[SUBSCRIPTION]    - trialDaysRemaining: nil
[SUBSCRIPTION]    - graceDaysRemaining: nil
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[APP_ACTIVE] 🏥 App became active - running subscription check...
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] 📊 Company Date Fields:
[SUBSCRIPTION]    - trialStartDate: nil
[SUBSCRIPTION]    - trialEndDate: nil
[SUBSCRIPTION]    - seatGraceStartDate: nil
[SUBSCRIPTION]    - subscriptionEnd: nil
[SUBSCRIPTION]    - subscriptionStatus: active
[SUBSCRIPTION]    - subscriptionPlan: business
[SUBSCRIPTION]    - maxSeats: 10
[SUBSCRIPTION]    - seatedEmployeeIds: 8 employees
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[SUBSCRIPTION] 📊 Computed Days Remaining:
[SUBSCRIPTION]    - trialDaysRemaining: nil
[SUBSCRIPTION]    - graceDaysRemaining: nil
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[SYNC] 🔌 Network state changed: Connected
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] 📊 Company Date Fields:
[SUBSCRIPTION]    - trialStartDate: nil
[SUBSCRIPTION]    - trialEndDate: nil
[SUBSCRIPTION]    - seatGraceStartDate: nil
[SUBSCRIPTION]    - subscriptionEnd: nil
[SUBSCRIPTION]    - subscriptionStatus: active
[SUBSCRIPTION]    - subscriptionPlan: business
[SUBSCRIPTION]    - maxSeats: 10
[SUBSCRIPTION]    - seatedEmployeeIds: 8 employees
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[SUBSCRIPTION] 📊 Computed Days Remaining:
[SUBSCRIPTION]    - trialDaysRemaining: nil
[SUBSCRIPTION]    - graceDaysRemaining: nil
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: true)
[APP_LAUNCH_SYNC] ✅ Full sync completed
[SYNC] 🔄 Connection active - triggering background sync (no alert)
[TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: false)
[TRIGGER_BG_SYNC] ✅ Starting forced full sync
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION CALLED
[SYNC_ALL] ========================================
[SYNC_ALL] 🔄 FULL SYNC STARTED
[SYNC_ALL] ========================================
[SYNC_ALL] Starting complete data sync...
[SYNC_DEBUG] [syncAll()] 📊 Starting complete data sync
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA BEFORE SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 8
[SYNC_DEBUG] [syncAll()]   - Clients: 83
[SYNC_DEBUG] [syncAll()]   - Task Types: 10
[SYNC_DEBUG] [syncAll()]   - Projects: 112
[SYNC_DEBUG] [syncAll()]   - Tasks: 131
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 80
[SYNC_DEBUG] [syncAll()] → Syncing Company...
[SYNC_DEBUG] [syncCompany()] 🔵 FUNCTION CALLED
[SYNC_COMPANY] 📊 Syncing company data...
[SYNC_DEBUG] [syncCompany()] 📥 Fetching company from API with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Fetching company with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1748465773440x642579687246238300
[TRIGGER_BG_SYNC] ✅ Starting background refresh
[SYNC_BG] 🔄 Background refresh...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: 2025-11-28 19:55:21 +0000)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1748465394255x432584139041047400, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1748465773440x642579687246238300
[PAGINATION] 📊 Starting paginated fetch for Project
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-05-28T20:56:13.474Z
[SUBSCRIPTION]   Modified Date: 2025-11-28T18:59:18.405Z
[SUBSCRIPTION] seatedEmployees field: (
    1753230317583x428571297099025200,
    1756840434099x951226537166325500,
    1753914761221x724121893642571000,
    1753328723013x504049467271405800,
    1754587884944x371337347971496300,
    1748465394255x432584139041047400,
    1763085768202x210761881388762620,
    1763086598301x843368719839049900
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "hasPrioritySupport": false,
        "subscriptionPeriod": "Annual",
        "qbConnected": false,
        "openHour": "08:00:00",
        "referralMethod": "Internet Advertisement",
        "stripeCustomerId": "cus_T36eGaT0hs9iJC",
        "Created By": "1748465394255x432584139041047400",
        "hasWebsite": true,
        "maxSeats": 10,
        "closeHour": "17:00:00",
        "companySize": "6-10",
        "companyId": "canprodeckandrail",
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1749588655579x140501417288366290/Canpro%20Comp%20Background%20Blue%20outline.png",
        "location": {
            "address": "2031 Malaview Ave W, Sidney, BC V8L 5X6, Canada",
            "lat": 48.6565189,
            "lng": -123.4147597
        },
        "subscriptionIds": [
            "1758568300709x540056355248731840"
        ],
        "calendarEventsList": [
            "1761105012740x872010881259677600",
            "1755227642166x391920373831565300",
            "1754701293025x694916300132843500",
            "1757107051642x734125747806666800",
            "1758566949155x212139951058321400",
            "1757352484786x589119037331210200",
            "1755226439282x133790218534256640",
            "1754975535026x738008031937691600",
            "1756408823654x857638691115106300",
            "1757963976267x289946640207577100",
            "1761537603476x623442883830261900",
            "1760910359838x670307039553519600",
            "1756058852049x303685419708186600",
            "1757968311543x435987416481529860",
            "1755306318562x371712687673704450",
            "1760561719490x898727191970054100",
            "1754975909817x377121006139473900",
            "1761176912434x945223368936687700",
            "1755827393818x704709020194701300",
            "1757352060964x316783380518666240",
            "1760910400351x270262116246093820",
            "1757963961641x521220792188403700",
            "1754701232865x525823177532112900",
            "1758500973646x792122813946265600",
            "1755227631020x764855806930190300",
            "1757107020503x946232342075932700",
            "1755227638993x625473504595148800",
            "1759881602520x113235755261493250",
            "1757353597161x433469544039186400",
            "1757353009581x521840467132547100",
            "1754975914679x695523862994223100",
            "1754701250873x168811570427592700",
            "1757964007882x422772079645687800",
            "1754975491164x655952437710684200",
            "1757352700797x916500593841537000",
            "1761598307359x369018276098114900",
            "1757107054134x769369811978027000",
            "1757107782863x667949950222467100",
            "1754974878859x297045775900999700",
            "1755561234657x563754053572493300",
            "1761598004029x529719586046166500",
            "1757107823314x987930736133668900",
            "1754975387790x691077226756046800",
            "1757352...
[CompanyDTO] Successfully decoded company with ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncCompany()] ✅ API returned company DTO
[SYNC_DEBUG] [syncCompany()]   - ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncCompany()]   - Name: Canpro Deck and Rail
[SYNC_DEBUG] [syncCompany()]   - Plan: business
[SYNC_DEBUG] [syncCompany()]   - Status: active
[SYNC_DEBUG] [syncCompany()] 🔍 Finding or creating local company record
[SYNC_DEBUG] [syncCompany()] ✅ Local company record ready: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncCompany()] 📝 Updating company properties...
[SYNC_COMPANY] 💺 Set 8 seated employees
[SYNC_DEBUG] [syncCompany()] 💾 Saving company to modelContext...
[SYNC_DEBUG] [syncCompany()] ✅ Company saved successfully
[SYNC_COMPANY] ✅ Company synced
[SYNC_DEBUG] [syncAll()] → Syncing Users...
[SYNC_DEBUG] [syncUsers()] 🔵 FUNCTION CALLED
[SYNC_USERS] 👥 Syncing users...
[SYNC_DEBUG] [syncUsers()] 📥 Fetching users from API for company: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB BEFORE sync: 8
[SYNC_DEBUG] [syncUsers()] 👑 Company has 1 admin IDs: ["1748465394255x432584139041047400"]
[SYNC_DEBUG] [syncUsers()] ✅ API returned 8 user DTOs
[SYNC_DEBUG] [syncUsers()]   - User: Jackson Sweet (ID: 1748465394255x432584139041047400, Role: Admin)
[SYNC_DEBUG] [syncUsers()]   - User: Jake Strickler (ID: 1753230317583x428571297099025200, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Michael Truong (ID: 1753328723013x504049467271405800, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Matthew Schure (ID: 1753914761221x724121893642571000, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Jason  Zavarella  (ID: 1754587884944x371337347971496300, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: jacky sweet (ID: 1754860945504x527568066085500700, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Harrison Sweet (ID: 1756840434099x951226537166325500, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Test User (ID: 1763086598301x843368719839049900, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()] 🔍 Handling deletions - remote IDs count: 8
[SYNC_DEBUG] [syncUsers()] 📝 Upserting 8 users...
[SYNC_DEBUG] [syncUsers()]   [1/8] Processing user: Jackson Sweet
[SYNC_DEBUG] [syncUsers()]     - 👑 Role set to ADMIN (in company.adminIds)
[SYNC_DEBUG] [syncUsers()]   [2/8] Processing user: Jake Strickler
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [3/8] Processing user: Michael Truong
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [4/8] Processing user: Matthew Schure
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [5/8] Processing user: Jason  Zavarella 
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [6/8] Processing user: jacky sweet
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [7/8] Processing user: Harrison Sweet
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [8/8] Processing user: Test User
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()] 💾 Saving 8 users to modelContext...
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB AFTER sync: 8
[SYNC_DEBUG] [syncUsers()] ✅ Users synced successfully
[SYNC_USERS] ✅ Synced 8 users
[SYNC_DEBUG] [syncAll()] → Syncing Clients...
[SYNC_CLIENTS] 🏢 Syncing clients...
[PAGINATION] 📄 Page 1: Fetched 100 Projects (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 12 Projects (Total: 112)
[PAGINATION] ✅ Completed: Total 112 Projects fetched across 2 page(s)
[SYNC_CLIENTS] ✅ Synced 83 clients
[SYNC_DEBUG] [syncAll()] → Syncing Task Types...
[SYNC_TASK_TYPES] 🏷️ Syncing task types...
[SUBSCRIPTION] Fetching company with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 112 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 112 project DTOs
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749586163701x396423366167232500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass and Picket Rail (ID: 1749586174866x110690431811190780, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Picket Rail (ID: 1749586179639x244283897333940220, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749690416370x985153191748829200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: White Picket Rail (ID: 1750357971084x306219215847686140, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1750804807288x943771560210858000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749586763048x120981950584586240, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1750441263328x140993402080329730, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1750795611716x994274982386466800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1749586801652x306929575411318800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1751909464495x180481289536143360, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1750883077033x590279256206213100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1750900614565x327808501247639550, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Picket Rail (ID: 1749586184856x285458931444613100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Rail Install (ID: 1750702746702x663636148225835000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl x6 (ID: 1750813137792x752192238878982100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Holly Cairns (ID: 1749680833010x699128756736622600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Fixes (ID: 1753664644191x202638343807434750, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Citygate Residences (ID: 1749586906996x865684734853775400, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Railings (ID: 1749680761120x249432494453030900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1753329352107x565711029445328900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1749586705585x714222645300428800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings and Vinyl (ID: 1751909808924x718010029027622900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1754616467606x548867552339296260, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 5 Rail (ID: 1753229083403x842793680537124900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1754344050927x534376409483444200, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Resheet and Rail (ID: 1749586692554x980569304335384600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tresah West (ID: 1754974772424x394875558941949950, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings and Vinyl (ID: 1753665362759x737226709855895600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1749586700318x333260304791896060, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1753664305487x793477197813514200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 6 Rail (ID: 1755041062592x511796567485186050, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Panel Replacement (ID: 1751910135367x966736171096866800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1752601051698x903591708844359700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Decking (ID: 1754589056247x254560566646407170, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Full Deck Reno (ID: 1750723765540x303180737839104000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1752175509422x898084395908333600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing (ID: 1756223399996x265341656389124100, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation (ID: 1756318908867x953426405689393200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1752776464410x661330533842681900, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059098285x737640461996654600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1750440730997x906438807705092100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757619145252x615683919055945700, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059151872x602924780431081500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757968311543x983159421449011200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1753119953246x993784723040370700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Resheet (ID: 1754589100629x510062438632128500, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Railings (ID: 1757107020503x716224716500107300, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352484786x500787665621745660, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1756173620534x428807569238130700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Deck (ID: 1758566949155x322399556269506560, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352060964x383151969287536640, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757107671518x879890653515874300, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1754701232865x677316667411529700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1757107764280x465129162957389800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1758296675282x126430031754559490, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757527016186x415582405950701600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation Project (ID: 1759686979934x711467728557310000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Re-Deck (ID: 1760561719490x137928777715679230, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vesta Building 5 (ID: 1760118200379x710220307553537400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Front Porch Renovation (ID: 1760910328770x208514094862172160, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 8 (ID: 1761250879945x291682334605312000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 7 Rail (ID: 1761176842238x780033636871278100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Atkins Vinyl (ID: 1761597111555x552548310082079800, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings install (ID: 1762137953322x554810481131449600, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762212590948x136520575044295040, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Craigflower Deck (ID: 1762556427348x517851484823765840, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 9 (ID: 1761354750585x647669498519535000, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Privacy Screen (ID: 1762543302380x321963360079808640, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Saltspring Deck (ID: 1760111175326x203699314919852700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1749680724033x411605712464773100, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horvath Residence (ID: 1761328499444x499552626562328260, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing installation (ID: 1761414925593x646467348213920800, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Foul Bay (ID: 1762561415426x996476274573631500, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 10 (ID: 1761418112304x398481473932432960, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749586719371x972858121489481700, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Rail (ID: 1750357551920x895437148222128100, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Rail (ID: 1750357561238x129060953598197760, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1757352687624x806108101695242200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762371872490x567527248234800400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762799607102x502441258643648400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Lagoon Road (ID: 1763597925759x528574641433569660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screws Replacement (ID: 1763598971410x856062415932827600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Patio Railings (ID: 1763670368893x658391771436205600, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 2 Decks Railings (ID: 1764016891269x257549011160044930, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project (ID: 1764349670924x285917647196505240, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: JR MARINE VINYL (ID: 1764353278600x477798836670142500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 4 (ID: 1764354204479x701605945345088000, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test calendar Project (ID: 1764356231188x400704020109447360, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1757968311543x983159421449011200, 1763670368893x658391771436205600, 1758296675282x126430031754559490, 1756059151872x602924780431081500, 1751909808924x718010029027622900, 1762543302380x321963360079808640, 1762212590948x136520575044295040, 1761176842238x780033636871278100, 1750357641278x823759340133941200, 1752776464410x661330533842681900...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 112
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1757968311543x983159421449011200, 1763670368893x658391771436205600, 1758296675282x126430031754559490, 1756059151872x602924780431081500, 1751909808924x718010029027622900, 1762543302380x321963360079808640, 1762212590948x136520575044295040, 1761176842238x780033636871278100, 1750357641278x823759340133941200, 1752776464410x661330533842681900...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 112
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 112 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/112] Processing project: Railings Install (ID: 1749586163701x396423366167232500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/112] Processing project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/112] Processing project: Glass and Picket Rail (ID: 1749586174866x110690431811190780)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585568315x752989628360556500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/112] Processing project: Picket Rail (ID: 1749586179639x244283897333940220)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585536859x712894814985912300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/112] Processing project: Railings Install (ID: 1749690416370x985153191748829200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749690410265x119717273779044350
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/112] Processing project: White Picket Rail (ID: 1750357971084x306219215847686140)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357954804x769945754465992700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/112] Processing project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/112] Processing project: Deck Renovation (ID: 1750804807288x943771560210858000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750804800457x472965554251235300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/112] Processing project: Railings Install (ID: 1749586763048x120981950584586240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586737310x106251394427125760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/112] Processing project: Vinyl Install (ID: 1750441263328x140993402080329730)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/112] Processing project: Railings Install (ID: 1750795611716x994274982386466800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750795605478x390008598584098800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/112] Processing project: Deck Renovation (ID: 1749586801652x306929575411318800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586792850x877118093711376400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/112] Processing project: Railings Install (ID: 1751909464495x180481289536143360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909457617x594711236472733700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/112] Processing project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357865603x137918885816172540
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/112] Processing project: Vinyl (ID: 1750883077033x590279256206213100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/112] Processing project: Railings Install (ID: 1750900614565x327808501247639550)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750900320558x218381647275622400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/112] Processing project: Picket Rail (ID: 1749586184856x285458931444613100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/112] Processing project: Rail Install (ID: 1750702746702x663636148225835000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750702709826x440207919174123500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/112] Processing project: Vinyl x6 (ID: 1750813137792x752192238878982100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750813127504x118028961055768580
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/112] Processing project: Holly Cairns (ID: 1749680833010x699128756736622600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/112] Processing project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440434867x551253418888396800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/112] Processing project: Railing Fixes (ID: 1753664644191x202638343807434750)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664632135x384475870734581760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/112] Processing project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664547384x343487592350089200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/112] Processing project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/112] Processing project: Citygate Residences (ID: 1749586906996x865684734853775400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586880440x144805284752916480
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/112] Processing project: Vinyl and Railings (ID: 1749680761120x249432494453030900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680754260x149217965145587700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/112] Processing project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/112] Processing project: Railings Install (ID: 1753329352107x565711029445328900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/112] Processing project: Deck Renovation (ID: 1749586705585x714222645300428800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583565285x288985074921373700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 15
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/112] Processing project: Railings and Vinyl (ID: 1751909808924x718010029027622900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909797690x496740713683222500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/112] Processing project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 82
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/112] Processing project: Railing Install (ID: 1754616467606x548867552339296260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/112] Processing project: Building 5 Rail (ID: 1753229083403x842793680537124900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/112] Processing project: Railings Install (ID: 1754344050927x534376409483444200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754344043861x565730719165055000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/112] Processing project: Resheet and Rail (ID: 1749586692554x980569304335384600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583613627x308318030964457500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [36/112] Processing project: Tresah West (ID: 1754974772424x394875558941949950)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754974748399x413357541168250900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 28
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [37/112] Processing project: Railings and Vinyl (ID: 1753665362759x737226709855895600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750882881128x444938477262340100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [38/112] Processing project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754975126372x683705610359275500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [39/112] Processing project: Railing Install (ID: 1749586700318x333260304791896060)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583584571x767122796235980800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [40/112] Processing project: Vinyl and Rail (ID: 1753664305487x793477197813514200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664294253x564318804406435840
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [41/112] Processing project: Building 6 Rail (ID: 1755041062592x511796567485186050)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 17
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [42/112] Processing project: Glass Panel Replacement (ID: 1751910135367x966736171096866800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751910125916x822849677225885700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [43/112] Processing project: Vinyl (ID: 1752601051698x903591708844359700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [44/112] Processing project: Composite Decking (ID: 1754589056247x254560566646407170)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754589047118x996161264968007700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [45/112] Processing project: Full Deck Reno (ID: 1750723765540x303180737839104000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [46/112] Processing project: Vinyl and Rail (ID: 1752175509422x898084395908333600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752175499756x266991785897361400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [47/112] Processing project: Railing (ID: 1756223399996x265341656389124100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756223387640x604868650966188000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [48/112] Processing project: Vinyl Installation (ID: 1756318908867x953426405689393200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756318887720x451321530312294400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [49/112] Processing project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [50/112] Processing project: Railings Install (ID: 1752776464410x661330533842681900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752776455322x754596679749468200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [51/112] Processing project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [52/112] Processing project: Vinyl Install (ID: 1756059098285x737640461996654600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756059089485x242277244056109060
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [53/112] Processing project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756058840326x700613386127802400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [54/112] Processing project: Deck Renovation (ID: 1750440730997x906438807705092100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440722423x521437779856982000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [55/112] Processing project: Railings Install (ID: 1757619145252x615683919055945700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757619044405x547608476400353300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [56/112] Processing project: Vinyl Install (ID: 1756059151872x602924780431081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1755709108282x800017647174680600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [57/112] Processing project: Vinyl Install (ID: 1757968311543x983159421449011200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757968285487x448325282704654340
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [58/112] Processing project: Railing Install (ID: 1753119953246x993784723040370700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753119944038x194042290990481400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [59/112] Processing project: Deck Resheet (ID: 1754589100629x510062438632128500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753329184350x142252864730824700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [60/112] Processing project: Vinyl and Railings (ID: 1757107020503x716224716500107300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [61/112] Processing project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758501288164x377092967591837700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [62/112] Processing project: Vinyl Install (ID: 1757352484786x500787665621745660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352466382x239269624074731520
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [63/112] Processing project: Railings Install (ID: 1756173620534x428807569238130700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756173604572x386075168328122400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 11
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [64/112] Processing project: Jenkins Deck (ID: 1758566949155x322399556269506560)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [65/112] Processing project: Vinyl Install (ID: 1757352060964x383151969287536640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106238143x262751318504374270
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [66/112] Processing project: Railings Install (ID: 1757107671518x879890653515874300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757107613901x267894212333404160
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [67/112] Processing project: Vinyl and Rail (ID: 1754701232865x677316667411529700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754701223029x590260382089871400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [68/112] Processing project: Vinyl (ID: 1757107764280x465129162957389800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106205768x951454637370900500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [69/112] Processing project: Vinyl Install (ID: 1758296675282x126430031754559490)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758296666824x961607219536461800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [70/112] Processing project: Vinyl Install (ID: 1757527016186x415582405950701600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [71/112] Processing project: Vinyl Installation Project (ID: 1759686979934x711467728557310000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759686973767x178860879946711040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [72/112] Processing project: Composite Re-Deck (ID: 1760561719490x137928777715679230)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760561707979x197729397940944900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [73/112] Processing project: Vesta Building 5 (ID: 1760118200379x710220307553537400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [74/112] Processing project: Front Porch Renovation (ID: 1760910328770x208514094862172160)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [75/112] Processing project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [76/112] Processing project: Building 8 (ID: 1761250879945x291682334605312000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [77/112] Processing project: Building 7 Rail (ID: 1761176842238x780033636871278100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [78/112] Processing project: Atkins Vinyl (ID: 1761597111555x552548310082079800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [79/112] Processing project: Railings install (ID: 1762137953322x554810481131449600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [80/112] Processing project: Railings (ID: 1762212590948x136520575044295040)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762212524670x699792906785419600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [81/112] Processing project: Craigflower Deck (ID: 1762556427348x517851484823765840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [82/112] Processing project: Building 9 (ID: 1761354750585x647669498519535000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [83/112] Processing project: Privacy Screen (ID: 1762543302380x321963360079808640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762543205170x577385652266722000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [84/112] Processing project: Saltspring Deck (ID: 1760111175326x203699314919852700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760111139605x960277442076944300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [85/112] Processing project: Vinyl and Rail (ID: 1749680724033x411605712464773100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680696083x161679526313852930
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [86/112] Processing project: Horvath Residence (ID: 1761328499444x499552626562328260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761328353725x669942620480408400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [87/112] Processing project: Railing installation (ID: 1761414925593x646467348213920800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761414897277x183883587450463400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [88/112] Processing project: Foul Bay (ID: 1762561415426x996476274573631500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762561357392x693270200856129800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 21
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [89/112] Processing project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762968020793x765300842349141900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [90/112] Processing project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [91/112] Processing project: Building 10 (ID: 1761418112304x398481473932432960)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [92/112] Processing project: Deck Reconstruction (ID: 1749586719371x972858121489481700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583538523x468672809532129300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [93/112] Processing project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [94/112] Processing project: Horizon North - Rail (ID: 1750357551920x895437148222128100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [95/112] Processing project: Horizon South - Rail (ID: 1750357561238x129060953598197760)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [96/112] Processing project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [97/112] Processing project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [98/112] Processing project: Vinyl and Rail (ID: 1757352687624x806108101695242200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352671325x989874668592693200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [99/112] Processing project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [100/112] Processing project: Railings (ID: 1762371872490x567527248234800400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762371868801x315967791419500900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [101/112] Processing project: Railings (ID: 1762799607102x502441258643648400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762799572400x485318112072851800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [102/112] Processing project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585908198x642156418531328000
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [103/112] Processing project: Lagoon Road (ID: 1763597925759x528574641433569660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [104/112] Processing project: Tek Screws Replacement (ID: 1763598971410x856062415932827600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [105/112] Processing project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661421924x864836316544519400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [106/112] Processing project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [107/112] Processing project: Patio Railings (ID: 1763670368893x658391771436205600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763670017305x311082176430490500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [108/112] Processing project: 2 Decks Railings (ID: 1764016891269x257549011160044930)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1764016753468x208913036148087970
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [109/112] Processing project: Test Project (ID: 1764349670924x285917647196505240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761448868740x424637742123653570
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [110/112] Processing project: JR MARINE VINYL (ID: 1764353278600x477798836670142500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1764353200445x724009481435708800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [111/112] Processing project: Test Project 4 (ID: 1764354204479x701605945345088000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [112/112] Processing project: Test calendar Project (ID: 1764356231188x400704020109447360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 112 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 112 projects
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-05-28T20:56:13.474Z
[SUBSCRIPTION]   Modified Date: 2025-11-28T18:59:18.405Z
[SUBSCRIPTION] seatedEmployees field: (
    1753230317583x428571297099025200,
    1756840434099x951226537166325500,
    1753914761221x724121893642571000,
    1753328723013x504049467271405800,
    1754587884944x371337347971496300,
    1748465394255x432584139041047400,
    1763085768202x210761881388762620,
    1763086598301x843368719839049900
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "hasPrioritySupport": false,
        "subscriptionPeriod": "Annual",
        "qbConnected": false,
        "openHour": "08:00:00",
        "referralMethod": "Internet Advertisement",
        "stripeCustomerId": "cus_T36eGaT0hs9iJC",
        "Created By": "1748465394255x432584139041047400",
        "hasWebsite": true,
        "maxSeats": 10,
        "closeHour": "17:00:00",
        "companySize": "6-10",
        "companyId": "canprodeckandrail",
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1749588655579x140501417288366290/Canpro%20Comp%20Background%20Blue%20outline.png",
        "location": {
            "address": "2031 Malaview Ave W, Sidney, BC V8L 5X6, Canada",
            "lat": 48.6565189,
            "lng": -123.4147597
        },
        "subscriptionIds": [
            "1758568300709x540056355248731840"
        ],
        "calendarEventsList": [
            "1761105012740x872010881259677600",
            "1755227642166x391920373831565300",
            "1754701293025x694916300132843500",
            "1757107051642x734125747806666800",
            "1758566949155x212139951058321400",
            "1757352484786x589119037331210200",
            "1755226439282x133790218534256640",
            "1754975535026x738008031937691600",
            "1756408823654x857638691115106300",
            "1757963976267x289946640207577100",
            "1761537603476x623442883830261900",
            "1760910359838x670307039553519600",
            "1756058852049x303685419708186600",
            "1757968311543x435987416481529860",
            "1755306318562x371712687673704450",
            "1760561719490x898727191970054100",
            "1754975909817x377121006139473900",
            "1761176912434x945223368936687700",
            "1755827393818x704709020194701300",
            "1757352060964x316783380518666240",
            "1760910400351x270262116246093820",
            "1757963961641x521220792188403700",
            "1754701232865x525823177532112900",
            "1758500973646x792122813946265600",
            "1755227631020x764855806930190300",
            "1757107020503x946232342075932700",
            "1755227638993x625473504595148800",
            "1759881602520x113235755261493250",
            "1757353597161x433469544039186400",
            "1757353009581x521840467132547100",
            "1754975914679x695523862994223100",
            "1754701250873x168811570427592700",
            "1757964007882x422772079645687800",
            "1754975491164x655952437710684200",
            "1757352700797x916500593841537000",
            "1761598307359x369018276098114900",
            "1757107054134x769369811978027000",
            "1757107782863x667949950222467100",
            "1754974878859x297045775900999700",
            "1755561234657x563754053572493300",
            "1761598004029x529719586046166500",
            "1757107823314x987930736133668900",
            "1754975387790x691077226756046800",
            "1757352...
[CompanyDTO] Successfully decoded company with ID: 1748465773440x642579687246238300
[PAGINATION] 📄 Page 1: Fetched 88 calendarevents (Total: 88)
[PAGINATION] ✅ Completed: Total 88 calendarevents fetched across 1 page(s)
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Allison Hobbs' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Mike Geric Construction' color from API: #9c9473
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Andrew Harcombe' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Thea McDonagh' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Andrew Harcombe' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Barb Bovell' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Traditional Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Traditional Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Matt Chester' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Matt Chester' color from API: #59779F
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #a25b4d
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1757106868986x707332498883870700
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1757106868986x627704676003872800
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: VINYL INSTALL
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Darveau' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759941002258x501096483456024600
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759941002258x624124640419381200
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK TYPE 2
[SYNC_CALENDAR] 🎨 Setting task event 'Scott Barnes' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759941010431x884485453751255000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759941010431x814990531789586400
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK TYPE 2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759954722494x797635100879618000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759954722494x566291647236931600
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK 4
[SYNC_CALENDAR] 🎨 Setting task event 'Angie Koessler' color from API: #a3b590
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Velocity Projects' color from API: #59779F
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Velocity Projects' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Paul O’Callaghan' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - 904 Deckboards and Railings' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Quote' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Deficiencies' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes - Building 10' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects - Citygate Residences' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1763342495287x758516607873589400
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Knappet Projects Inc
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glass Install - Building 9' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dynamic Deck and Fence' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Morley Wittman - 2 Decks Railings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Jennifer Hulke / Alex' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client - Test Project' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Steve Horvath' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Allison Hobbs - Railings Install' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - Test calendar Project' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs - Deck Resheet' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - Test calendar Project' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Darveau' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Paul Etheridge' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761617663057x210554420367211170
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Craig Asselin
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761638579535x530167553036626750
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Test Client
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761638593098x201677834454842000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Test Client
[SYNC_CALENDAR] 🎨 Setting task event 'Patrick Jennings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #C2C2C2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Rail Install' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client - Test Project' color from API: #4d7ea2
[SYNC_CALENDAR] ✅ Synced 88 calendar events
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[SYNC_TASK_TYPES] ✅ Synced 10 task types
[SYNC_DEBUG] [syncAll()] → Syncing Projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: nil)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1748465394255x432584139041047400, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1748465773440x642579687246238300
[PAGINATION] 📊 Starting paginated fetch for Project
[MAIN_TAB_VIEW] onAppear - Initial user role: Optional(OPS.UserRole.admin)
[MAIN_TAB_VIEW] onAppear - Current user: Optional("Jackson Sweet")
[MAIN_TAB_VIEW] onAppear - Tab count: 4
[APP_MESSAGE] 🔍 Checking for active app messages...
[APP_MESSAGE] Fetching active message from: https://opsapp.co/api/1.1/obj/AppMessage?constraints=%5B%7B%22value%22:true,%22key%22:%22active%22,%22constraint_type%22:%22equals%22%7D%5D&sort_field=Created%20Date&descending=true&limit=1
App is being debugged, do not track this hang
Hang detected: 1.66s (debugger attached, not reporting)
[PAGINATION] 📄 Page 1: Fetched 100 Projects (Total: 100)
[PAGINATION] 📄 Page 1: Fetched 100 Tasks (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 12 Projects (Total: 112)
[PAGINATION] ✅ Completed: Total 112 Projects fetched across 2 page(s)
[PAGINATION] 📄 Page 2: Fetched 31 Tasks (Total: 131)
[PAGINATION] ✅ Completed: Total 131 Tasks fetched across 2 page(s)
[APP_MESSAGE] Response status: 200
[APP_MESSAGE] Raw JSON response:
{
    "response": {
        "cursor": 0,
        "results": [],
        "count": 0,
        "remaining": 0
    }
}
[APP_MESSAGE] No active messages found
Failed to locate resource named "default.csv"
App is being debugged, do not track this hang
Hang detected: 2.71s (debugger attached, not reporting)
[UNASSIGNED_ROLES] Fetching company users for company: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 112 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 112 project DTOs
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749586163701x396423366167232500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass and Picket Rail (ID: 1749586174866x110690431811190780, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Picket Rail (ID: 1749586179639x244283897333940220, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749690416370x985153191748829200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: White Picket Rail (ID: 1750357971084x306219215847686140, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1750804807288x943771560210858000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1749586763048x120981950584586240, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1750441263328x140993402080329730, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1750795611716x994274982386466800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1749586801652x306929575411318800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1751909464495x180481289536143360, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1750883077033x590279256206213100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1750900614565x327808501247639550, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Picket Rail (ID: 1749586184856x285458931444613100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Rail Install (ID: 1750702746702x663636148225835000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl x6 (ID: 1750813137792x752192238878982100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Holly Cairns (ID: 1749680833010x699128756736622600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Fixes (ID: 1753664644191x202638343807434750, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Citygate Residences (ID: 1749586906996x865684734853775400, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Railings (ID: 1749680761120x249432494453030900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1753329352107x565711029445328900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1749586705585x714222645300428800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings and Vinyl (ID: 1751909808924x718010029027622900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1754616467606x548867552339296260, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 5 Rail (ID: 1753229083403x842793680537124900, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1754344050927x534376409483444200, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Resheet and Rail (ID: 1749586692554x980569304335384600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tresah West (ID: 1754974772424x394875558941949950, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings and Vinyl (ID: 1753665362759x737226709855895600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1749586700318x333260304791896060, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1753664305487x793477197813514200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 6 Rail (ID: 1755041062592x511796567485186050, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Panel Replacement (ID: 1751910135367x966736171096866800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1752601051698x903591708844359700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Decking (ID: 1754589056247x254560566646407170, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Full Deck Reno (ID: 1750723765540x303180737839104000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1752175509422x898084395908333600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing (ID: 1756223399996x265341656389124100, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation (ID: 1756318908867x953426405689393200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1752776464410x661330533842681900, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059098285x737640461996654600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1750440730997x906438807705092100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757619145252x615683919055945700, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059151872x602924780431081500, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757968311543x983159421449011200, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing Install (ID: 1753119953246x993784723040370700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Resheet (ID: 1754589100629x510062438632128500, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Railings (ID: 1757107020503x716224716500107300, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352484786x500787665621745660, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1756173620534x428807569238130700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Deck (ID: 1758566949155x322399556269506560, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352060964x383151969287536640, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757107671518x879890653515874300, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1754701232865x677316667411529700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1757107764280x465129162957389800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1758296675282x126430031754559490, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757527016186x415582405950701600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation Project (ID: 1759686979934x711467728557310000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Re-Deck (ID: 1760561719490x137928777715679230, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vesta Building 5 (ID: 1760118200379x710220307553537400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Front Porch Renovation (ID: 1760910328770x208514094862172160, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 8 (ID: 1761250879945x291682334605312000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 7 Rail (ID: 1761176842238x780033636871278100, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Atkins Vinyl (ID: 1761597111555x552548310082079800, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings install (ID: 1762137953322x554810481131449600, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762212590948x136520575044295040, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Craigflower Deck (ID: 1762556427348x517851484823765840, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 9 (ID: 1761354750585x647669498519535000, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Privacy Screen (ID: 1762543302380x321963360079808640, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Saltspring Deck (ID: 1760111175326x203699314919852700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1749680724033x411605712464773100, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horvath Residence (ID: 1761328499444x499552626562328260, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railing installation (ID: 1761414925593x646467348213920800, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Foul Bay (ID: 1762561415426x996476274573631500, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 10 (ID: 1761418112304x398481473932432960, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749586719371x972858121489481700, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Rail (ID: 1750357551920x895437148222128100, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Rail (ID: 1750357561238x129060953598197760, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1757352687624x806108101695242200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762371872490x567527248234800400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762799607102x502441258643648400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Lagoon Road (ID: 1763597925759x528574641433569660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screws Replacement (ID: 1763598971410x856062415932827600, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Patio Railings (ID: 1763670368893x658391771436205600, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 2 Decks Railings (ID: 1764016891269x257549011160044930, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project (ID: 1764349670924x285917647196505240, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: JR MARINE VINYL (ID: 1764353278600x477798836670142500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 4 (ID: 1764354204479x701605945345088000, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test calendar Project (ID: 1764356231188x400704020109447360, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1749586719371x972858121489481700, 1749586179639x244283897333940220, 1764356231188x400704020109447360, 1761354750585x647669498519535000, 1762799607102x502441258643648400, 1754616467606x548867552339296260, 1750440730997x906438807705092100, 1751909464495x180481289536143360, 1749586906996x865684734853775400, 1750440442155x307170934474407940...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 112
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1749586719371x972858121489481700, 1749586179639x244283897333940220, 1764356231188x400704020109447360, 1761354750585x647669498519535000, 1762799607102x502441258643648400, 1754616467606x548867552339296260, 1750440730997x906438807705092100, 1751909464495x180481289536143360, 1749586906996x865684734853775400, 1750440442155x307170934474407940...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 112
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 112 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/112] Processing project: Railings Install (ID: 1749586163701x396423366167232500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/112] Processing project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/112] Processing project: Glass and Picket Rail (ID: 1749586174866x110690431811190780)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585568315x752989628360556500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/112] Processing project: Picket Rail (ID: 1749586179639x244283897333940220)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585536859x712894814985912300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/112] Processing project: Railings Install (ID: 1749690416370x985153191748829200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749690410265x119717273779044350
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/112] Processing project: White Picket Rail (ID: 1750357971084x306219215847686140)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357954804x769945754465992700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/112] Processing project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/112] Processing project: Deck Renovation (ID: 1750804807288x943771560210858000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750804800457x472965554251235300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/112] Processing project: Railings Install (ID: 1749586763048x120981950584586240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586737310x106251394427125760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/112] Processing project: Vinyl Install (ID: 1750441263328x140993402080329730)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/112] Processing project: Railings Install (ID: 1750795611716x994274982386466800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750795605478x390008598584098800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/112] Processing project: Deck Renovation (ID: 1749586801652x306929575411318800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586792850x877118093711376400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/112] Processing project: Railings Install (ID: 1751909464495x180481289536143360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909457617x594711236472733700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/112] Processing project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357865603x137918885816172540
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/112] Processing project: Vinyl (ID: 1750883077033x590279256206213100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/112] Processing project: Railings Install (ID: 1750900614565x327808501247639550)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750900320558x218381647275622400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/112] Processing project: Picket Rail (ID: 1749586184856x285458931444613100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/112] Processing project: Rail Install (ID: 1750702746702x663636148225835000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750702709826x440207919174123500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/112] Processing project: Vinyl x6 (ID: 1750813137792x752192238878982100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750813127504x118028961055768580
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/112] Processing project: Holly Cairns (ID: 1749680833010x699128756736622600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/112] Processing project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440434867x551253418888396800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/112] Processing project: Railing Fixes (ID: 1753664644191x202638343807434750)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664632135x384475870734581760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/112] Processing project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664547384x343487592350089200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/112] Processing project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/112] Processing project: Citygate Residences (ID: 1749586906996x865684734853775400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586880440x144805284752916480
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/112] Processing project: Vinyl and Railings (ID: 1749680761120x249432494453030900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680754260x149217965145587700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/112] Processing project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/112] Processing project: Railings Install (ID: 1753329352107x565711029445328900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/112] Processing project: Deck Renovation (ID: 1749586705585x714222645300428800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583565285x288985074921373700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 15
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/112] Processing project: Railings and Vinyl (ID: 1751909808924x718010029027622900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909797690x496740713683222500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/112] Processing project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 82
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/112] Processing project: Railing Install (ID: 1754616467606x548867552339296260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/112] Processing project: Building 5 Rail (ID: 1753229083403x842793680537124900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/112] Processing project: Railings Install (ID: 1754344050927x534376409483444200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754344043861x565730719165055000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/112] Processing project: Resheet and Rail (ID: 1749586692554x980569304335384600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583613627x308318030964457500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [36/112] Processing project: Tresah West (ID: 1754974772424x394875558941949950)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754974748399x413357541168250900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 28
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [37/112] Processing project: Railings and Vinyl (ID: 1753665362759x737226709855895600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750882881128x444938477262340100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [38/112] Processing project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754975126372x683705610359275500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [39/112] Processing project: Railing Install (ID: 1749586700318x333260304791896060)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583584571x767122796235980800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [40/112] Processing project: Vinyl and Rail (ID: 1753664305487x793477197813514200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664294253x564318804406435840
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [41/112] Processing project: Building 6 Rail (ID: 1755041062592x511796567485186050)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 17
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [42/112] Processing project: Glass Panel Replacement (ID: 1751910135367x966736171096866800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751910125916x822849677225885700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [43/112] Processing project: Vinyl (ID: 1752601051698x903591708844359700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [44/112] Processing project: Composite Decking (ID: 1754589056247x254560566646407170)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754589047118x996161264968007700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [45/112] Processing project: Full Deck Reno (ID: 1750723765540x303180737839104000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [46/112] Processing project: Vinyl and Rail (ID: 1752175509422x898084395908333600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752175499756x266991785897361400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [47/112] Processing project: Railing (ID: 1756223399996x265341656389124100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756223387640x604868650966188000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [48/112] Processing project: Vinyl Installation (ID: 1756318908867x953426405689393200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756318887720x451321530312294400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [49/112] Processing project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [50/112] Processing project: Railings Install (ID: 1752776464410x661330533842681900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752776455322x754596679749468200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [51/112] Processing project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [52/112] Processing project: Vinyl Install (ID: 1756059098285x737640461996654600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756059089485x242277244056109060
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [53/112] Processing project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756058840326x700613386127802400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [54/112] Processing project: Deck Renovation (ID: 1750440730997x906438807705092100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440722423x521437779856982000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [55/112] Processing project: Railings Install (ID: 1757619145252x615683919055945700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757619044405x547608476400353300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [56/112] Processing project: Vinyl Install (ID: 1756059151872x602924780431081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1755709108282x800017647174680600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [57/112] Processing project: Vinyl Install (ID: 1757968311543x983159421449011200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757968285487x448325282704654340
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [58/112] Processing project: Railing Install (ID: 1753119953246x993784723040370700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753119944038x194042290990481400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [59/112] Processing project: Deck Resheet (ID: 1754589100629x510062438632128500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753329184350x142252864730824700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [60/112] Processing project: Vinyl and Railings (ID: 1757107020503x716224716500107300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [61/112] Processing project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758501288164x377092967591837700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [62/112] Processing project: Vinyl Install (ID: 1757352484786x500787665621745660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352466382x239269624074731520
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [63/112] Processing project: Railings Install (ID: 1756173620534x428807569238130700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756173604572x386075168328122400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 11
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [64/112] Processing project: Jenkins Deck (ID: 1758566949155x322399556269506560)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [65/112] Processing project: Vinyl Install (ID: 1757352060964x383151969287536640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106238143x262751318504374270
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [66/112] Processing project: Railings Install (ID: 1757107671518x879890653515874300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757107613901x267894212333404160
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [67/112] Processing project: Vinyl and Rail (ID: 1754701232865x677316667411529700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754701223029x590260382089871400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [68/112] Processing project: Vinyl (ID: 1757107764280x465129162957389800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106205768x951454637370900500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [69/112] Processing project: Vinyl Install (ID: 1758296675282x126430031754559490)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758296666824x961607219536461800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [70/112] Processing project: Vinyl Install (ID: 1757527016186x415582405950701600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [71/112] Processing project: Vinyl Installation Project (ID: 1759686979934x711467728557310000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759686973767x178860879946711040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [72/112] Processing project: Composite Re-Deck (ID: 1760561719490x137928777715679230)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760561707979x197729397940944900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [73/112] Processing project: Vesta Building 5 (ID: 1760118200379x710220307553537400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [74/112] Processing project: Front Porch Renovation (ID: 1760910328770x208514094862172160)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [75/112] Processing project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [76/112] Processing project: Building 8 (ID: 1761250879945x291682334605312000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [77/112] Processing project: Building 7 Rail (ID: 1761176842238x780033636871278100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [78/112] Processing project: Atkins Vinyl (ID: 1761597111555x552548310082079800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [79/112] Processing project: Railings install (ID: 1762137953322x554810481131449600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [80/112] Processing project: Railings (ID: 1762212590948x136520575044295040)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762212524670x699792906785419600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [81/112] Processing project: Craigflower Deck (ID: 1762556427348x517851484823765840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [82/112] Processing project: Building 9 (ID: 1761354750585x647669498519535000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [83/112] Processing project: Privacy Screen (ID: 1762543302380x321963360079808640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762543205170x577385652266722000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [84/112] Processing project: Saltspring Deck (ID: 1760111175326x203699314919852700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760111139605x960277442076944300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [85/112] Processing project: Vinyl and Rail (ID: 1749680724033x411605712464773100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680696083x161679526313852930
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [86/112] Processing project: Horvath Residence (ID: 1761328499444x499552626562328260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761328353725x669942620480408400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [87/112] Processing project: Railing installation (ID: 1761414925593x646467348213920800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761414897277x183883587450463400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [88/112] Processing project: Foul Bay (ID: 1762561415426x996476274573631500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762561357392x693270200856129800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 21
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [89/112] Processing project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762968020793x765300842349141900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [90/112] Processing project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [91/112] Processing project: Building 10 (ID: 1761418112304x398481473932432960)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [92/112] Processing project: Deck Reconstruction (ID: 1749586719371x972858121489481700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583538523x468672809532129300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [93/112] Processing project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [94/112] Processing project: Horizon North - Rail (ID: 1750357551920x895437148222128100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [95/112] Processing project: Horizon South - Rail (ID: 1750357561238x129060953598197760)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [96/112] Processing project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [97/112] Processing project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [98/112] Processing project: Vinyl and Rail (ID: 1757352687624x806108101695242200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352671325x989874668592693200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [99/112] Processing project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [100/112] Processing project: Railings (ID: 1762371872490x567527248234800400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762371868801x315967791419500900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [101/112] Processing project: Railings (ID: 1762799607102x502441258643648400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762799572400x485318112072851800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [102/112] Processing project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585908198x642156418531328000
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [103/112] Processing project: Lagoon Road (ID: 1763597925759x528574641433569660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [104/112] Processing project: Tek Screws Replacement (ID: 1763598971410x856062415932827600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [105/112] Processing project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661421924x864836316544519400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [106/112] Processing project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [107/112] Processing project: Patio Railings (ID: 1763670368893x658391771436205600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763670017305x311082176430490500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [108/112] Processing project: 2 Decks Railings (ID: 1764016891269x257549011160044930)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1764016753468x208913036148087970
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [109/112] Processing project: Test Project (ID: 1764349670924x285917647196505240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761448868740x424637742123653570
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [110/112] Processing project: JR MARINE VINYL (ID: 1764353278600x477798836670142500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1764353200445x724009481435708800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [111/112] Processing project: Test Project 4 (ID: 1764354204479x701605945345088000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [112/112] Processing project: Test calendar Project (ID: 1764356231188x400704020109447360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 112 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 112
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 112 projects
[SYNC_DEBUG] [syncAll()] → Syncing Tasks...
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[SYNC_TASKS] 👥 Task 1755561341868x827590313571516400 has 3 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1760038146098x334745038654831400 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760039874648x826176346946007300 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760045782362x955161365026995000 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760047704959x275870687555464600 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760048319255x606214943435433300 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760979888629x204968343478490140 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039686x743344587893171700 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039781x693658104439007500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039831x104741326289121250 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1761176911826x204855785962333900 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761521129413x880107951179489800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761521129416x468097832888645400 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1761521148940x608449854147496300 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761537602812x719721977414008800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761598306364x932012097634360700 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1761601745043x563654837393551500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761601745089x413273478679222900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1761602708960x821435761142251800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761603223485x174664657895305500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761619179312x208149455980926720 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762212616205x752353163780604000 has 2 team members: ["1753230317583x428571297099025200", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1762371923915x337351352249871000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762543334135x553598135701023400 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762556480969x598094383819240100 has 1 team members: ["1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1762558126067x964132028322863900 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762558144979x541499217214724800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561523763x401188218309090050 has 3 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000", "1754860945504x527568066085500700"]
[SYNC_TASKS] 👥 Task 1762561541366x517416056216506400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561746669x824911295137660000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561906235x415617011209397100 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762711466271x759084250722583200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762888275108x172215528934953400 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762888943104x820474174405652100 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762990543021x905935528224593500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763002029999x582763900362554200 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1763002956554x571935808405140030 has 2 team members: ["1748465394255x432584139041047400", "1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1763002973273x175987915805661000 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763060835591x326503206775735600 has 2 team members: ["1748465394255x432584139041047400", "1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1763424538881x301268872876463600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763598022828x751510376851150800 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763598971810x476945141904835600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763661573099x156990438721998000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763756748767x562046986736548540 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764016891753x798187412124544000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764031516068x572574407511603500 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1764091890734x452489178527755200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764349671363x923219644619226000 has 1 team members: ["1754860945504x527568066085500700"]
[SYNC_TASKS] 👥 Task 1764351152229x272397096543026680 has 2 team members: ["1753230317583x428571297099025200", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1764356231536x896737753426054500 has 6 team members: ["1748465394255x432584139041047400", "1754860945504x527568066085500700", "1748465394255x432584139041047400", "1754860945504x527568066085500700", "1754860945504x527568066085500700", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1757107782863x390894053080956900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757353009581x503553803935547400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1758500973646x822688391783514100 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762905761042x684085461805061840 has 3 team members: ["1756840434099x951226537166325500", "1763086598301x843368719839049900", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763696372477x793930042240040000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757353597161x892791827831193600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761537079115x698149494366627700 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1754701250873x792659897679872000 has 2 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1754701293025x554478622390091800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754974878859x120131612466741250 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754975387790x320866109902553100 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975488676x486791870649991200 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975491164x231380377644302340 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754975535026x819361087173427200 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1754975909817x342744308839088100 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975914679x858050460260499500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755226439282x716350574369177600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755226452045x769737969815519200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755227631020x612030476241862700 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1755227635686x987193543227867100 has 2 team members: ["1753914761221x724121893642571000", "1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1755227638993x162852363413225470 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755227642166x260251987390234620 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755306318562x614500739220766700 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1755306336831x722088858503086000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755561234657x716022755531161600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755827393818x781839586218999800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1756408823654x423283733254635500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757107051642x660367893178351600 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757107054134x286282726509903870 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757352251597x657956268556681200 has 2 team members: ["1753914761221x724121893642571000", "1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1757352700797x150964085611560960 has 3 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757963961641x391174037760901100 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1757963976267x431291518291279900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757964007882x695872239588343800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763661484611x438296031222977800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763670370289x100864899084366130 has 1 team members: ["1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1763670373456x512719474980343400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] ✅ Synced 131 tasks
[SYNC_BG] ✅ Background refresh complete
[APP_MESSAGE] ❌ No active message found
[UNASSIGNED_ROLES] Found 0 users without employeeType
[PAGINATION] 📄 Page 1: Fetched 100 Tasks (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 31 Tasks (Total: 131)
[PAGINATION] ✅ Completed: Total 131 Tasks fetched across 2 page(s)
[SYNC_TASKS] 👥 Task 1755561341868x827590313571516400 has 3 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1760038146098x334745038654831400 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760039874648x826176346946007300 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760045782362x955161365026995000 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760047704959x275870687555464600 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760048319255x606214943435433300 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1760979888629x204968343478490140 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039686x743344587893171700 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039781x693658104439007500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1760988039831x104741326289121250 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1761176911826x204855785962333900 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761521129413x880107951179489800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761521129416x468097832888645400 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1761521148940x608449854147496300 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761537602812x719721977414008800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761598306364x932012097634360700 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1761601745043x563654837393551500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761601745089x413273478679222900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1761602708960x821435761142251800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761603223485x174664657895305500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761619179312x208149455980926720 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762212616205x752353163780604000 has 2 team members: ["1753230317583x428571297099025200", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1762371923915x337351352249871000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762543334135x553598135701023400 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762556480969x598094383819240100 has 1 team members: ["1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1762558126067x964132028322863900 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762558144979x541499217214724800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561523763x401188218309090050 has 3 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000", "1754860945504x527568066085500700"]
[SYNC_TASKS] 👥 Task 1762561541366x517416056216506400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561746669x824911295137660000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762561906235x415617011209397100 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762711466271x759084250722583200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762888275108x172215528934953400 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762888943104x820474174405652100 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1762990543021x905935528224593500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763002029999x582763900362554200 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1763002956554x571935808405140030 has 2 team members: ["1748465394255x432584139041047400", "1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1763002973273x175987915805661000 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763060835591x326503206775735600 has 2 team members: ["1748465394255x432584139041047400", "1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1763424538881x301268872876463600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763598022828x751510376851150800 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763598971810x476945141904835600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763661573099x156990438721998000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763756748767x562046986736548540 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764016891753x798187412124544000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764031516068x572574407511603500 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1764091890734x452489178527755200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1764349671363x923219644619226000 has 1 team members: ["1754860945504x527568066085500700"]
[SYNC_TASKS] 👥 Task 1764351152229x272397096543026680 has 2 team members: ["1753230317583x428571297099025200", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1764356231536x896737753426054500 has 6 team members: ["1748465394255x432584139041047400", "1754860945504x527568066085500700", "1748465394255x432584139041047400", "1754860945504x527568066085500700", "1754860945504x527568066085500700", "1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1757107782863x390894053080956900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757353009581x503553803935547400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1758500973646x822688391783514100 has 2 team members: ["1756840434099x951226537166325500", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1762905761042x684085461805061840 has 3 team members: ["1756840434099x951226537166325500", "1763086598301x843368719839049900", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1763696372477x793930042240040000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757353597161x892791827831193600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1761537079115x698149494366627700 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1754701250873x792659897679872000 has 2 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1754701293025x554478622390091800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754974878859x120131612466741250 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754975387790x320866109902553100 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975488676x486791870649991200 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975491164x231380377644302340 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1754975535026x819361087173427200 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1754975909817x342744308839088100 has 1 team members: ["1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1754975914679x858050460260499500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755226439282x716350574369177600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755226452045x769737969815519200 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755227631020x612030476241862700 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1755227635686x987193543227867100 has 2 team members: ["1753914761221x724121893642571000", "1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1755227638993x162852363413225470 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755227642166x260251987390234620 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755306318562x614500739220766700 has 1 team members: ["1753914761221x724121893642571000"]
[SYNC_TASKS] 👥 Task 1755306336831x722088858503086000 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755561234657x716022755531161600 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1755827393818x781839586218999800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1756408823654x423283733254635500 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757107051642x660367893178351600 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757107054134x286282726509903870 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1757352251597x657956268556681200 has 2 team members: ["1753914761221x724121893642571000", "1753328723013x504049467271405800"]
[SYNC_TASKS] 👥 Task 1757352700797x150964085611560960 has 3 team members: ["1753328723013x504049467271405800", "1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757963961641x391174037760901100 has 1 team members: ["1754587884944x371337347971496300"]
[SYNC_TASKS] 👥 Task 1757963976267x431291518291279900 has 2 team members: ["1753914761221x724121893642571000", "1756840434099x951226537166325500"]
[SYNC_TASKS] 👥 Task 1757964007882x695872239588343800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763661484611x438296031222977800 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] 👥 Task 1763670370289x100864899084366130 has 1 team members: ["1748465394255x432584139041047400"]
[SYNC_TASKS] 👥 Task 1763670373456x512719474980343400 has 1 team members: ["1753230317583x428571297099025200"]
[SYNC_TASKS] ✅ Synced 131 tasks
[SYNC_DEBUG] [syncAll()] → Syncing Calendar Events...
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[PAGINATION] 📄 Page 1: Fetched 88 calendarevents (Total: 88)
[PAGINATION] ✅ Completed: Total 88 calendarevents fetched across 1 page(s)
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Allison Hobbs' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Mike Geric Construction' color from API: #9c9473
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Andrew Harcombe' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Thea McDonagh' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Brian Fraser' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Andrew Harcombe' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Barb Bovell' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Natalie Fischer' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Traditional Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Amed' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glen Saito' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Traditional Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Matt Chester' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Matt Chester' color from API: #59779F
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #a25b4d
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1757106868986x707332498883870700
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1757106868986x627704676003872800
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: VINYL INSTALL
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Darveau' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759941002258x501096483456024600
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759941002258x624124640419381200
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK TYPE 2
[SYNC_CALENDAR] 🎨 Setting task event 'Scott Barnes' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759941010431x884485453751255000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759941010431x814990531789586400
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK TYPE 2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759954722494x797635100879618000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759954722494x566291647236931600
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: TEST TASK 4
[SYNC_CALENDAR] 🎨 Setting task event 'Angie Koessler' color from API: #a3b590
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Velocity Projects' color from API: #59779F
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Just Wright Reno' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Velocity Projects' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Paul O’Callaghan' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - 904 Deckboards and Railings' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Quote' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Deficiencies' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes - Building 10' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Verity Projects - Citygate Residences' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1763342495287x758516607873589400
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Knappet Projects Inc
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glass Install - Building 9' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dynamic Deck and Fence' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Morley Wittman - 2 Decks Railings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Jennifer Hulke / Alex' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client - Test Project' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Steve Horvath' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Allison Hobbs - Railings Install' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - Test calendar Project' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Anna Krebs - Deck Resheet' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client 2 - Test calendar Project' color from API: #819079
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Darveau' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Paul Etheridge' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761617663057x210554420367211170
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Craig Asselin
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761638579535x530167553036626750
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Test Client
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1761638593098x201677834454842000
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Test Client
[SYNC_CALENDAR] 🎨 Setting task event 'Patrick Jennings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #C2C2C2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Rail Install' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Test Client - Test Project' color from API: #4d7ea2
[SYNC_CALENDAR] ✅ Synced 88 calendar events
[SYNC_DEBUG] [syncAll()] → Linking Relationships...
[LINK_RELATIONSHIPS] 🔗 Linking all relationships...
[LINK_RELATIONSHIPS] ✅ Linked 708 relationships
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA AFTER SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 8
[SYNC_DEBUG] [syncAll()]   - Clients: 83
[SYNC_DEBUG] [syncAll()]   - Task Types: 10
[SYNC_DEBUG] [syncAll()]   - Projects: 112
[SYNC_DEBUG] [syncAll()]   - Tasks: 131
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 80
[SYNC_DEBUG] [syncAll()] ✅ Complete sync finished successfully at 2025-11-28 19:55:29 +0000
[SYNC_ALL] ✅ Complete sync finished
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION EXITING - syncInProgress set to false
[SYNC_ALL] ========================================
[SYNC_ALL] 🏁 FULL SYNC COMPLETED
[SYNC_ALL] ========================================
[PRELOAD] Starting background client data preload
[PRELOAD] Preloaded 83 clients with project data
Failed to locate resource named "default.csv"
[REFRESH_CLIENT] 🔄 Refreshing client 1762371868801x315967791419500900
[SUBSCRIPTION] Fetching client with ID: 1762371868801x315967791419500900
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/client/1762371868801x315967791419500900
[REFRESH_CLIENT] ✅ Client refreshed
