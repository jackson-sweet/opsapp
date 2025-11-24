[SYNC] 📱 Initial connection state: Connected
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
[APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)
[SYNC] 🔌 Network state changed: Connected
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: true)
[APP_ACTIVE] 🏥 App became active - checking data health...
[APP_LAUNCH_SYNC] ✅ Full sync completed
[DATA_HEALTH] 🔎 Checking for minimum required data...
[DATA_HEALTH] ✅ Minimum required data present
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 8/10
[SUBSCRIPTION] User admin check: true (user: 1748465394255x432584139041047400, admins: 1)
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
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
[SYNC_DEBUG] [syncAll()]   - Clients: 81
[SYNC_DEBUG] [syncAll()]   - Task Types: 10
[SYNC_DEBUG] [syncAll()]   - Projects: 107
[SYNC_DEBUG] [syncAll()]   - Tasks: 123
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 72
[SYNC_DEBUG] [syncAll()] → Syncing Company...
[SYNC_DEBUG] [syncCompany()] 🔵 FUNCTION CALLED
[SYNC_COMPANY] 📊 Syncing company data...
[SYNC_DEBUG] [syncCompany()] 📥 Fetching company from API with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Fetching company with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1748465773440x642579687246238300
App is being debugged, do not track this hang
Hang detected: 3.15s (debugger attached, not reporting)
[TRIGGER_BG_SYNC] ✅ Starting background refresh
[SYNC_BG] 🔄 Background refresh...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: 2025-11-23 19:55:25 +0000)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1748465394255x432584139041047400, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1748465773440x642579687246238300
[PAGINATION] 📊 Starting paginated fetch for Project
[MAIN_TAB_VIEW] onAppear - Initial user role: Optional(OPS.UserRole.admin)
[MAIN_TAB_VIEW] onAppear - Current user: Optional("Jackson Sweet")
[MAIN_TAB_VIEW] onAppear - Tab count: 4
App is being debugged, do not track this hang
Hang detected: 2.52s (debugger attached, not reporting)
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-05-28T20:56:13.474Z
[SUBSCRIPTION]   Modified Date: 2025-11-21T20:25:50.558Z
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
            "1757352251597x858207992043536400",
            "1754975488676x410783548935503900",
            "1755227635686x176833022750359550",
            "1755226452045x124062882646982660",
            "1760979889473x404467925850889660",
            "1755561341868x174854584695521280",
            "1758296675282x948606259142852600",
            "1755306336831x672898918435520500",
            "1761617663057x210554420367211170",
            "1761618546619x575444185968433400",
            "1761634113189x644389907096438500",
            "1761638242312x810467664657835600",
            "1761638579535x530167553036626750",
            "1761638593098x201677834454842000",
            "1762212592139x481150489772960600",
            "1762212616726x338849986229004860",
            "1762371924606x800520568934815400",
            "1762543303425x625831592536173700",
            "1762543...
[CompanyDTO] Successfully decoded company with ID: 1748465773440x642579687246238300
[PAGINATION] 📄 Page 1: Fetched 100 Projects (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 7 Projects (Total: 107)
[PAGINATION] ✅ Completed: Total 107 Projects fetched across 2 page(s)
Failed to locate resource named "default.csv"
App is being debugged, do not track this hang
Hang detected: 5.31s (debugger attached, not reporting)
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
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 107 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 107 project DTOs
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059098285x737640461996654600, Status: Completed)
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1756173620534x428807569238130700, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Deck (ID: 1758566949155x322399556269506560, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352060964x383151969287536640, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757107671518x879890653515874300, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1754701232865x677316667411529700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1757107764280x465129162957389800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1758296675282x126430031754559490, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757527016186x415582405950701600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation Project (ID: 1759686979934x711467728557310000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Re-Deck (ID: 1760561719490x137928777715679230, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vesta Building 5 (ID: 1760118200379x710220307553537400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Front Porch Renovation (ID: 1760910328770x208514094862172160, Status: Completed)
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Foul Bay (ID: 1762561415426x996476274573631500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 10 (ID: 1761418112304x398481473932432960, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749586719371x972858121489481700, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Rail (ID: 1750357551920x895437148222128100, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Rail (ID: 1750357561238x129060953598197760, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1757352687624x806108101695242200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762371872490x567527248234800400, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762799607102x502441258643648400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Lagoon Road (ID: 1763597925759x528574641433569660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screws Replacement (ID: 1763598971410x856062415932827600, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Patio Railings (ID: 1763670368893x658391771436205600, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1763661484158x167450309826011840, 1750357971084x306219215847686140, 1749586906996x865684734853775400, 1757527016186x415582405950701600, 1757107764280x465129162957389800, 1751909808924x718010029027622900, 1750795611716x994274982386466800, 1757107671518x879890653515874300, 1749680724033x411605712464773100, 1762968072445x295643492003265540...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 107
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1763661484158x167450309826011840, 1750357971084x306219215847686140, 1749586906996x865684734853775400, 1757527016186x415582405950701600, 1757107764280x465129162957389800, 1751909808924x718010029027622900, 1750795611716x994274982386466800, 1757107671518x879890653515874300, 1749680724033x411605712464773100, 1762968072445x295643492003265540...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 107
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 107 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/107] Processing project: Railings Install (ID: 1749586163701x396423366167232500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/107] Processing project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/107] Processing project: Glass and Picket Rail (ID: 1749586174866x110690431811190780)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585568315x752989628360556500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/107] Processing project: Picket Rail (ID: 1749586179639x244283897333940220)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585536859x712894814985912300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/107] Processing project: Railings Install (ID: 1749690416370x985153191748829200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749690410265x119717273779044350
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/107] Processing project: White Picket Rail (ID: 1750357971084x306219215847686140)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357954804x769945754465992700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/107] Processing project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/107] Processing project: Deck Renovation (ID: 1750804807288x943771560210858000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750804800457x472965554251235300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/107] Processing project: Railings Install (ID: 1749586763048x120981950584586240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586737310x106251394427125760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/107] Processing project: Vinyl Install (ID: 1750441263328x140993402080329730)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/107] Processing project: Railings Install (ID: 1750795611716x994274982386466800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750795605478x390008598584098800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/107] Processing project: Deck Renovation (ID: 1749586801652x306929575411318800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586792850x877118093711376400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/107] Processing project: Railings Install (ID: 1751909464495x180481289536143360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909457617x594711236472733700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/107] Processing project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357865603x137918885816172540
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/107] Processing project: Vinyl (ID: 1750883077033x590279256206213100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/107] Processing project: Railings Install (ID: 1750900614565x327808501247639550)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750900320558x218381647275622400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/107] Processing project: Picket Rail (ID: 1749586184856x285458931444613100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/107] Processing project: Rail Install (ID: 1750702746702x663636148225835000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750702709826x440207919174123500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/107] Processing project: Vinyl x6 (ID: 1750813137792x752192238878982100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750813127504x118028961055768580
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/107] Processing project: Holly Cairns (ID: 1749680833010x699128756736622600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/107] Processing project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440434867x551253418888396800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/107] Processing project: Railing Fixes (ID: 1753664644191x202638343807434750)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664632135x384475870734581760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/107] Processing project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664547384x343487592350089200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/107] Processing project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/107] Processing project: Citygate Residences (ID: 1749586906996x865684734853775400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586880440x144805284752916480
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/107] Processing project: Vinyl and Railings (ID: 1749680761120x249432494453030900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680754260x149217965145587700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/107] Processing project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/107] Processing project: Railings Install (ID: 1753329352107x565711029445328900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/107] Processing project: Deck Renovation (ID: 1749586705585x714222645300428800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583565285x288985074921373700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 15
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/107] Processing project: Railings and Vinyl (ID: 1751909808924x718010029027622900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909797690x496740713683222500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/107] Processing project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 82
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/107] Processing project: Railing Install (ID: 1754616467606x548867552339296260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/107] Processing project: Building 5 Rail (ID: 1753229083403x842793680537124900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/107] Processing project: Railings Install (ID: 1754344050927x534376409483444200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754344043861x565730719165055000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/107] Processing project: Resheet and Rail (ID: 1749586692554x980569304335384600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583613627x308318030964457500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [36/107] Processing project: Tresah West (ID: 1754974772424x394875558941949950)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754974748399x413357541168250900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 28
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [37/107] Processing project: Railings and Vinyl (ID: 1753665362759x737226709855895600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750882881128x444938477262340100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [38/107] Processing project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754975126372x683705610359275500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [39/107] Processing project: Railing Install (ID: 1749586700318x333260304791896060)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583584571x767122796235980800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [40/107] Processing project: Vinyl and Rail (ID: 1753664305487x793477197813514200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664294253x564318804406435840
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [41/107] Processing project: Building 6 Rail (ID: 1755041062592x511796567485186050)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 17
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [42/107] Processing project: Glass Panel Replacement (ID: 1751910135367x966736171096866800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751910125916x822849677225885700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [43/107] Processing project: Vinyl (ID: 1752601051698x903591708844359700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [44/107] Processing project: Composite Decking (ID: 1754589056247x254560566646407170)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754589047118x996161264968007700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [45/107] Processing project: Full Deck Reno (ID: 1750723765540x303180737839104000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [46/107] Processing project: Vinyl and Rail (ID: 1752175509422x898084395908333600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752175499756x266991785897361400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [47/107] Processing project: Railing (ID: 1756223399996x265341656389124100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756223387640x604868650966188000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [48/107] Processing project: Vinyl Installation (ID: 1756318908867x953426405689393200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756318887720x451321530312294400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [49/107] Processing project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [50/107] Processing project: Railings Install (ID: 1752776464410x661330533842681900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752776455322x754596679749468200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [51/107] Processing project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [52/107] Processing project: Vinyl Install (ID: 1756059098285x737640461996654600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756059089485x242277244056109060
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [53/107] Processing project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756058840326x700613386127802400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [54/107] Processing project: Deck Renovation (ID: 1750440730997x906438807705092100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440722423x521437779856982000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [55/107] Processing project: Railings Install (ID: 1757619145252x615683919055945700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757619044405x547608476400353300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [56/107] Processing project: Vinyl Install (ID: 1756059151872x602924780431081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1755709108282x800017647174680600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [57/107] Processing project: Vinyl Install (ID: 1757968311543x983159421449011200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757968285487x448325282704654340
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [58/107] Processing project: Railing Install (ID: 1753119953246x993784723040370700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753119944038x194042290990481400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [59/107] Processing project: Deck Resheet (ID: 1754589100629x510062438632128500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753329184350x142252864730824700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [60/107] Processing project: Vinyl and Railings (ID: 1757107020503x716224716500107300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [61/107] Processing project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758501288164x377092967591837700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [62/107] Processing project: Vinyl Install (ID: 1757352484786x500787665621745660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352466382x239269624074731520
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [63/107] Processing project: Railings Install (ID: 1756173620534x428807569238130700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756173604572x386075168328122400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 11
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [64/107] Processing project: Jenkins Deck (ID: 1758566949155x322399556269506560)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [65/107] Processing project: Vinyl Install (ID: 1757352060964x383151969287536640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106238143x262751318504374270
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [66/107] Processing project: Railings Install (ID: 1757107671518x879890653515874300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757107613901x267894212333404160
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [67/107] Processing project: Vinyl and Rail (ID: 1754701232865x677316667411529700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754701223029x590260382089871400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [68/107] Processing project: Vinyl (ID: 1757107764280x465129162957389800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106205768x951454637370900500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [69/107] Processing project: Vinyl Install (ID: 1758296675282x126430031754559490)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758296666824x961607219536461800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [70/107] Processing project: Vinyl Install (ID: 1757527016186x415582405950701600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [71/107] Processing project: Vinyl Installation Project (ID: 1759686979934x711467728557310000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759686973767x178860879946711040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [72/107] Processing project: Composite Re-Deck (ID: 1760561719490x137928777715679230)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760561707979x197729397940944900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [73/107] Processing project: Vesta Building 5 (ID: 1760118200379x710220307553537400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [74/107] Processing project: Front Porch Renovation (ID: 1760910328770x208514094862172160)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [75/107] Processing project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [76/107] Processing project: Building 8 (ID: 1761250879945x291682334605312000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [77/107] Processing project: Building 7 Rail (ID: 1761176842238x780033636871278100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [78/107] Processing project: Atkins Vinyl (ID: 1761597111555x552548310082079800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [79/107] Processing project: Railings install (ID: 1762137953322x554810481131449600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [80/107] Processing project: Railings (ID: 1762212590948x136520575044295040)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762212524670x699792906785419600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [81/107] Processing project: Craigflower Deck (ID: 1762556427348x517851484823765840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [82/107] Processing project: Building 9 (ID: 1761354750585x647669498519535000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [83/107] Processing project: Privacy Screen (ID: 1762543302380x321963360079808640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762543205170x577385652266722000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [84/107] Processing project: Saltspring Deck (ID: 1760111175326x203699314919852700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760111139605x960277442076944300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [85/107] Processing project: Vinyl and Rail (ID: 1749680724033x411605712464773100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680696083x161679526313852930
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [86/107] Processing project: Horvath Residence (ID: 1761328499444x499552626562328260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761328353725x669942620480408400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [87/107] Processing project: Railing installation (ID: 1761414925593x646467348213920800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761414897277x183883587450463400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [88/107] Processing project: Foul Bay (ID: 1762561415426x996476274573631500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762561357392x693270200856129800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 21
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [89/107] Processing project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762968020793x765300842349141900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [90/107] Processing project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [91/107] Processing project: Building 10 (ID: 1761418112304x398481473932432960)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [92/107] Processing project: Deck Reconstruction (ID: 1749586719371x972858121489481700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583538523x468672809532129300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [93/107] Processing project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [94/107] Processing project: Horizon North - Rail (ID: 1750357551920x895437148222128100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [95/107] Processing project: Horizon South - Rail (ID: 1750357561238x129060953598197760)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [96/107] Processing project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [97/107] Processing project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [98/107] Processing project: Vinyl and Rail (ID: 1757352687624x806108101695242200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352671325x989874668592693200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [99/107] Processing project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [100/107] Processing project: Railings (ID: 1762371872490x567527248234800400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762371868801x315967791419500900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [101/107] Processing project: Railings (ID: 1762799607102x502441258643648400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762799572400x485318112072851800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [102/107] Processing project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585908198x642156418531328000
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [103/107] Processing project: Lagoon Road (ID: 1763597925759x528574641433569660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [104/107] Processing project: Tek Screws Replacement (ID: 1763598971410x856062415932827600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [105/107] Processing project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661421924x864836316544519400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [106/107] Processing project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [107/107] Processing project: Patio Railings (ID: 1763670368893x658391771436205600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763670017305x311082176430490500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 107 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 107 projects
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
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
[PAGINATION] 📄 Page 1: Fetched 80 calendarevents (Total: 80)
[PAGINATION] ✅ Completed: Total 80 calendarevents fetched across 1 page(s)
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
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Quote' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Deficiencies' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes - Building 10' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Patrick Jennings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Steve Horvath' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Jennifer Hulke / Alex' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1763342495287x758516607873589400
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Knappet Projects Inc
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glass Install - Building 9' color from API: #ceb4b4
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
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #C2C2C2
[SYNC_CALENDAR] 🎨 Setting task event 'Dynamic Deck and Fence' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Rail Install' color from API: #a25b4d
[SYNC_CALENDAR] ✅ Synced 80 calendar events
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[PAGINATION] 📄 Page 1: Fetched 100 Tasks (Total: 100)
[SYNC_CLIENTS] ✅ Synced 81 clients
[SYNC_DEBUG] [syncAll()] → Syncing Task Types...
[SYNC_TASK_TYPES] 🏷️ Syncing task types...
[SUBSCRIPTION] Fetching company with ID: 1748465773440x642579687246238300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1748465773440x642579687246238300
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-05-28T20:56:13.474Z
[SUBSCRIPTION]   Modified Date: 2025-11-21T20:25:50.558Z
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
            "1757352251597x858207992043536400",
            "1754975488676x410783548935503900",
            "1755227635686x176833022750359550",
            "1755226452045x124062882646982660",
            "1760979889473x404467925850889660",
            "1755561341868x174854584695521280",
            "1758296675282x948606259142852600",
            "1755306336831x672898918435520500",
            "1761617663057x210554420367211170",
            "1761618546619x575444185968433400",
            "1761634113189x644389907096438500",
            "1761638242312x810467664657835600",
            "1761638579535x530167553036626750",
            "1761638593098x201677834454842000",
            "1762212592139x481150489772960600",
            "1762212616726x338849986229004860",
            "1762371924606x800520568934815400",
            "1762543303425x625831592536173700",
            "1762543...
[CompanyDTO] Successfully decoded company with ID: 1748465773440x642579687246238300
[PAGINATION] 📄 Page 2: Fetched 23 Tasks (Total: 123)
[PAGINATION] ✅ Completed: Total 123 Tasks fetched across 2 page(s)
[SYNC_TASKS] ✅ Synced 123 tasks
[SYNC_BG] ✅ Background refresh complete
[SYNC_TASK_TYPES] ✅ Synced 10 task types
[SYNC_DEBUG] [syncAll()] → Syncing Projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: nil)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1748465394255x432584139041047400, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1748465773440x642579687246238300
[PAGINATION] 📊 Starting paginated fetch for Project
[PAGINATION] 📄 Page 1: Fetched 100 Projects (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 7 Projects (Total: 107)
[PAGINATION] ✅ Completed: Total 107 Projects fetched across 2 page(s)
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 107 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 107 project DTOs
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1756059098285x737640461996654600, Status: Completed)
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1756173620534x428807569238130700, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Jenkins Deck (ID: 1758566949155x322399556269506560, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757352060964x383151969287536640, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Install (ID: 1757107671518x879890653515874300, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1754701232865x677316667411529700, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl (ID: 1757107764280x465129162957389800, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1758296675282x126430031754559490, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1757527016186x415582405950701600, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation Project (ID: 1759686979934x711467728557310000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Re-Deck (ID: 1760561719490x137928777715679230, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vesta Building 5 (ID: 1760118200379x710220307553537400, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Front Porch Renovation (ID: 1760910328770x208514094862172160, Status: Completed)
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
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Foul Bay (ID: 1762561415426x996476274573631500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Building 10 (ID: 1761418112304x398481473932432960, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749586719371x972858121489481700, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Rail (ID: 1750357551920x895437148222128100, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Rail (ID: 1750357561238x129060953598197760, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1757352687624x806108101695242200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762371872490x567527248234800400, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1762799607102x502441258643648400, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Lagoon Road (ID: 1763597925759x528574641433569660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screws Replacement (ID: 1763598971410x856062415932827600, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Patio Railings (ID: 1763670368893x658391771436205600, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1763661484158x167450309826011840, 1750357971084x306219215847686140, 1749586906996x865684734853775400, 1757527016186x415582405950701600, 1757107764280x465129162957389800, 1751909808924x718010029027622900, 1750795611716x994274982386466800, 1757107671518x879890653515874300, 1749680724033x411605712464773100, 1762968072445x295643492003265540...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 107
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1763661484158x167450309826011840, 1750357971084x306219215847686140, 1749586906996x865684734853775400, 1757527016186x415582405950701600, 1757107764280x465129162957389800, 1751909808924x718010029027622900, 1750795611716x994274982386466800, 1757107671518x879890653515874300, 1749680724033x411605712464773100, 1762968072445x295643492003265540...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 107
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 107 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/107] Processing project: Railings Install (ID: 1749586163701x396423366167232500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/107] Processing project: Jason Schott Vinyl (ID: 1749680813361x893784236089671700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/107] Processing project: Glass and Picket Rail (ID: 1749586174866x110690431811190780)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585568315x752989628360556500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/107] Processing project: Picket Rail (ID: 1749586179639x244283897333940220)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585536859x712894814985912300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/107] Processing project: Railings Install (ID: 1749690416370x985153191748829200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749690410265x119717273779044350
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/107] Processing project: White Picket Rail (ID: 1750357971084x306219215847686140)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357954804x769945754465992700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/107] Processing project: Jenkins Townhouses, A & B (ID: 1750357641278x823759340133941200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/107] Processing project: Deck Renovation (ID: 1750804807288x943771560210858000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750804800457x472965554251235300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/107] Processing project: Railings Install (ID: 1749586763048x120981950584586240)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586737310x106251394427125760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/107] Processing project: Vinyl Install (ID: 1750441263328x140993402080329730)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/107] Processing project: Railings Install (ID: 1750795611716x994274982386466800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750795605478x390008598584098800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/107] Processing project: Deck Renovation (ID: 1749586801652x306929575411318800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586792850x877118093711376400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/107] Processing project: Railings Install (ID: 1751909464495x180481289536143360)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909457617x594711236472733700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/107] Processing project: 904 Deckboards and Railings (ID: 1750357880017x846296683032346600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357865603x137918885816172540
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/107] Processing project: Vinyl (ID: 1750883077033x590279256206213100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/107] Processing project: Railings Install (ID: 1750900614565x327808501247639550)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750900320558x218381647275622400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/107] Processing project: Picket Rail (ID: 1749586184856x285458931444613100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585523820x829074033484234800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/107] Processing project: Rail Install (ID: 1750702746702x663636148225835000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750702709826x440207919174123500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/107] Processing project: Vinyl x6 (ID: 1750813137792x752192238878982100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750813127504x118028961055768580
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/107] Processing project: Holly Cairns (ID: 1749680833010x699128756736622600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/107] Processing project: 3 Decks Vinyl (ID: 1750440442155x307170934474407940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440434867x551253418888396800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/107] Processing project: Railing Fixes (ID: 1753664644191x202638343807434750)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664632135x384475870734581760
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/107] Processing project: Railing Fixes/Glass Replacement (ID: 1753664556193x907149083175026700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664547384x343487592350089200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/107] Processing project: Seaport Apt Vinyl (ID: 1750357514979x398464044845236200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/107] Processing project: Citygate Residences (ID: 1749586906996x865684734853775400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749586880440x144805284752916480
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/107] Processing project: Vinyl and Railings (ID: 1749680761120x249432494453030900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680754260x149217965145587700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/107] Processing project: Kentwood Vinyl and Rail (ID: 1751568451629x743820634658963500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/107] Processing project: Railings Install (ID: 1753329352107x565711029445328900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750883072509x760414259317309400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/107] Processing project: Deck Renovation (ID: 1749586705585x714222645300428800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583565285x288985074921373700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 15
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/107] Processing project: Railings and Vinyl (ID: 1751909808924x718010029027622900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751909797690x496740713683222500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/107] Processing project: Nicholas Lowe Vinyl (ID: 1752521064469x642153251691561000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 82
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/107] Processing project: Railing Install (ID: 1754616467606x548867552339296260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/107] Processing project: Building 5 Rail (ID: 1753229083403x842793680537124900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/107] Processing project: Railings Install (ID: 1754344050927x534376409483444200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754344043861x565730719165055000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/107] Processing project: Resheet and Rail (ID: 1749586692554x980569304335384600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583613627x308318030964457500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [36/107] Processing project: Tresah West (ID: 1754974772424x394875558941949950)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754974748399x413357541168250900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 28
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [37/107] Processing project: Railings and Vinyl (ID: 1753665362759x737226709855895600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750882881128x444938477262340100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [38/107] Processing project: Under Door Vinyl Patch (ID: 1754975329223x976269891498410000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754975126372x683705610359275500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [39/107] Processing project: Railing Install (ID: 1749586700318x333260304791896060)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583584571x767122796235980800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [40/107] Processing project: Vinyl and Rail (ID: 1753664305487x793477197813514200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753664294253x564318804406435840
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [41/107] Processing project: Building 6 Rail (ID: 1755041062592x511796567485186050)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 17
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [42/107] Processing project: Glass Panel Replacement (ID: 1751910135367x966736171096866800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751910125916x822849677225885700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [43/107] Processing project: Vinyl (ID: 1752601051698x903591708844359700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 18
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [44/107] Processing project: Composite Decking (ID: 1754589056247x254560566646407170)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754589047118x996161264968007700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [45/107] Processing project: Full Deck Reno (ID: 1750723765540x303180737839104000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750723750832x790163818231365600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [46/107] Processing project: Vinyl and Rail (ID: 1752175509422x898084395908333600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752175499756x266991785897361400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [47/107] Processing project: Railing (ID: 1756223399996x265341656389124100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756223387640x604868650966188000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [48/107] Processing project: Vinyl Installation (ID: 1756318908867x953426405689393200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756318887720x451321530312294400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [49/107] Processing project: Unit 217 Plywood/Vinyl (ID: 1756318957577x767576178516557800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [50/107] Processing project: Railings Install (ID: 1752776464410x661330533842681900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752776455322x754596679749468200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [51/107] Processing project: Ray Horne Vinyl (ID: 1754344307323x705476695751655400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [52/107] Processing project: Vinyl Install (ID: 1756059098285x737640461996654600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756059089485x242277244056109060
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [53/107] Processing project: Swap Teks, Cut Stair Lags (ID: 1756058852049x281178897094017020)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756058840326x700613386127802400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [54/107] Processing project: Deck Renovation (ID: 1750440730997x906438807705092100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750440722423x521437779856982000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [55/107] Processing project: Railings Install (ID: 1757619145252x615683919055945700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757619044405x547608476400353300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [56/107] Processing project: Vinyl Install (ID: 1756059151872x602924780431081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1755709108282x800017647174680600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [57/107] Processing project: Vinyl Install (ID: 1757968311543x983159421449011200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757968285487x448325282704654340
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 13
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [58/107] Processing project: Railing Install (ID: 1753119953246x993784723040370700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753119944038x194042290990481400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [59/107] Processing project: Deck Resheet (ID: 1754589100629x510062438632128500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753329184350x142252864730824700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [60/107] Processing project: Vinyl and Railings (ID: 1757107020503x716224716500107300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 7
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [61/107] Processing project: Strip Weld Vinyl (ID: 1758501348670x421246168123047940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758501288164x377092967591837700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [62/107] Processing project: Vinyl Install (ID: 1757352484786x500787665621745660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352466382x239269624074731520
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [63/107] Processing project: Railings Install (ID: 1756173620534x428807569238130700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1756173604572x386075168328122400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 11
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [64/107] Processing project: Jenkins Deck (ID: 1758566949155x322399556269506560)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [65/107] Processing project: Vinyl Install (ID: 1757352060964x383151969287536640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106238143x262751318504374270
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 19
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [66/107] Processing project: Railings Install (ID: 1757107671518x879890653515874300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757107613901x267894212333404160
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [67/107] Processing project: Vinyl and Rail (ID: 1754701232865x677316667411529700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1754701223029x590260382089871400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 12
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [68/107] Processing project: Vinyl (ID: 1757107764280x465129162957389800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757106205768x951454637370900500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 14
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [69/107] Processing project: Vinyl Install (ID: 1758296675282x126430031754559490)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758296666824x961607219536461800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 8
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [70/107] Processing project: Vinyl Install (ID: 1757527016186x415582405950701600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [71/107] Processing project: Vinyl Installation Project (ID: 1759686979934x711467728557310000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759686973767x178860879946711040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [72/107] Processing project: Composite Re-Deck (ID: 1760561719490x137928777715679230)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760561707979x197729397940944900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [73/107] Processing project: Vesta Building 5 (ID: 1760118200379x710220307553537400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [74/107] Processing project: Front Porch Renovation (ID: 1760910328770x208514094862172160)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1751568415733x724999757118308400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [75/107] Processing project: Vinyl Lap up wall sheeting (ID: 1761001199537x620966590288318600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [76/107] Processing project: Building 8 (ID: 1761250879945x291682334605312000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [77/107] Processing project: Building 7 Rail (ID: 1761176842238x780033636871278100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [78/107] Processing project: Atkins Vinyl (ID: 1761597111555x552548310082079800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357596987x905404584325808100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [79/107] Processing project: Railings install (ID: 1762137953322x554810481131449600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1752601041616x312730317888946200
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 9
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [80/107] Processing project: Railings (ID: 1762212590948x136520575044295040)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762212524670x699792906785419600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [81/107] Processing project: Craigflower Deck (ID: 1762556427348x517851484823765840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757526946156x688268806035865600
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [82/107] Processing project: Building 9 (ID: 1761354750585x647669498519535000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [83/107] Processing project: Privacy Screen (ID: 1762543302380x321963360079808640)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762543205170x577385652266722000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [84/107] Processing project: Saltspring Deck (ID: 1760111175326x203699314919852700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760111139605x960277442076944300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [85/107] Processing project: Vinyl and Rail (ID: 1749680724033x411605712464773100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680696083x161679526313852930
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 20
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [86/107] Processing project: Horvath Residence (ID: 1761328499444x499552626562328260)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761328353725x669942620480408400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [87/107] Processing project: Railing installation (ID: 1761414925593x646467348213920800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761414897277x183883587450463400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 6
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [88/107] Processing project: Foul Bay (ID: 1762561415426x996476274573631500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762561357392x693270200856129800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 21
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [89/107] Processing project: Tsaykum Vinyl (ID: 1762968072445x295643492003265540)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762968020793x765300842349141900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [90/107] Processing project: 904 Deckboards and Railings (ID: 1763696370410x103094832446483980)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1759880954380x501191862237265900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [91/107] Processing project: Building 10 (ID: 1761418112304x398481473932432960)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1753229058713x559437269109833700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [92/107] Processing project: Deck Reconstruction (ID: 1749586719371x972858121489481700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749583538523x468672809532129300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [93/107] Processing project: Roof Deck Vinyl (ID: 1750357528336x586281681948770300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1750357487125x991796633895698400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [94/107] Processing project: Horizon North - Rail (ID: 1750357551920x895437148222128100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [95/107] Processing project: Horizon South - Rail (ID: 1750357561238x129060953598197760)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [96/107] Processing project: Horizon North - Vinyl (ID: 1750357571568x625400034168406000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [97/107] Processing project: Horizon South - Vinyl (ID: 1750357581701x622964747253579800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585776842x559055523026042900
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [98/107] Processing project: Vinyl and Rail (ID: 1757352687624x806108101695242200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1757352671325x989874668592693200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [99/107] Processing project: Knappet Esquimalt Vinyl Fix (ID: 1760977611035x182891765863614880)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760118168616x989382191601122300
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [100/107] Processing project: Railings (ID: 1762371872490x567527248234800400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762371868801x315967791419500900
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [101/107] Processing project: Railings (ID: 1762799607102x502441258643648400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1762799572400x485318112072851800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [102/107] Processing project: Quadra Affordable Housing (ID: 1763441666974x482142826558450000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749585908198x642156418531328000
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [103/107] Processing project: Lagoon Road (ID: 1763597925759x528574641433569660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749680782323x296798302282186750
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [104/107] Processing project: Tek Screws Replacement (ID: 1763598971410x856062415932827600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [105/107] Processing project: Tek Replacement Lexington (ID: 1763661484158x167450309826011840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661421924x864836316544519400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [106/107] Processing project: Tek Screw Replacement Chesterfield (ID: 1763661572520x409045265022997000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763598903652x306804650688889960
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [107/107] Processing project: Patio Railings (ID: 1763670368893x658391771436205600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1748465773440x642579687246238300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763670017305x311082176430490500
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 107 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 107
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 107 projects
[SYNC_DEBUG] [syncAll()] → Syncing Tasks...
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[PAGINATION] 📄 Page 1: Fetched 100 Tasks (Total: 100)
[PAGINATION] 📄 Page 2: Fetched 23 Tasks (Total: 123)
[PAGINATION] ✅ Completed: Total 123 Tasks fetched across 2 page(s)
[SYNC_TASKS] ✅ Synced 123 tasks
[SYNC_DEBUG] [syncAll()] → Syncing Calendar Events...
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[PAGINATION] 📄 Page 1: Fetched 80 calendarevents (Total: 80)
[PAGINATION] ✅ Completed: Total 80 calendarevents fetched across 1 page(s)
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
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Craig Asselin' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Quote' color from API: #d1c9b3
[SYNC_CALENDAR] 🎨 Setting task event 'Deficiencies' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'General Work' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes - Building 10' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Patrick Jennings' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Steve Horvath' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Jennifer Hulke / Alex' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Dustin Goertzen' color from API: #4d7ea2
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1763342495287x758516607873589400
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: nil
[SYNC_CALENDAR]    - CompanyID: 1748465773440x642579687246238300
[SYNC_CALENDAR]    - Title: Knappet Projects Inc
[SYNC_CALENDAR] 🎨 Setting task event 'Stephanie Jackson' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Glass Install - Building 9' color from API: #ceb4b4
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
[SYNC_CALENDAR] 🎨 Setting task event 'Cleanline Construction' color from API: #a25b4d
[SYNC_CALENDAR] 🎨 Setting task event 'Gablecraft Homes' color from API: #ceb4b4
[SYNC_CALENDAR] 🎨 Setting task event 'Jordan Tapping' color from API: #C2C2C2
[SYNC_CALENDAR] 🎨 Setting task event 'Dynamic Deck and Fence' color from API: #4d7ea2
[SYNC_CALENDAR] 🎨 Setting task event 'Rail Install' color from API: #a25b4d
[SYNC_CALENDAR] ✅ Synced 80 calendar events
[SYNC_DEBUG] [syncAll()] → Linking Relationships...
[LINK_RELATIONSHIPS] 🔗 Linking all relationships...
[LINK_RELATIONSHIPS] ✅ Linked 586 relationships
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA AFTER SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 8
[SYNC_DEBUG] [syncAll()]   - Clients: 81
[SYNC_DEBUG] [syncAll()]   - Task Types: 10
[SYNC_DEBUG] [syncAll()]   - Projects: 107
[SYNC_DEBUG] [syncAll()]   - Tasks: 123
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 72
[SYNC_DEBUG] [syncAll()] ✅ Complete sync finished successfully at 2025-11-23 19:55:40 +0000
[SYNC_ALL] ✅ Complete sync finished
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION EXITING - syncInProgress set to false
[SYNC_ALL] ========================================
[SYNC_ALL] 🏁 FULL SYNC COMPLETED
[SYNC_ALL] ========================================
<0x106de2e40> Gesture: System gesture gate timed out.
App is being debugged, do not track this hang
Hang detected: 2.02s (debugger attached, not reporting)
<0x106de2e40> Gesture: System gesture gate timed out.
App is being debugged, do not track this hang
Hang detected: 6.05s (debugger attached, not reporting)
[LOGOUT] Starting logout process...
[MAIN_TAB_VIEW] User role changed from Optional(OPS.UserRole.admin) to nil
[MAIN_TAB_VIEW] After role change - Tab count: 4
[MAIN_TAB_VIEW] currentUser ID changed
[MAIN_TAB_VIEW]   Old ID: Optional("1748465394255x432584139041047400")
[MAIN_TAB_VIEW]   New ID: nil
[LOGOUT] Performing complete data wipe...
[LOGOUT] Deleting all SwiftData models...
[LOGOUT] Deleting 72 calendar events...
[LOGOUT] Deleting 123 tasks...
[LOGOUT] Deleting 10 task types...
[LOGOUT] Deleting 107 projects...
[LOGOUT] Deleting 81 clients...
[LOGOUT] Deleting 8 team members...
[LOGOUT] Deleting 8 users...
[LOGOUT] Deleting 1 companies...
CoreData: debug: PostSaveMaintenance: incremental_vacuum with freelist_count - 63 and pages_to_free 12
[LOGOUT] All data deleted and saved
[LOGOUT] All caches cleared
[LOGOUT] Data wipe complete
App is being debugged, do not track this hang
Hang detected: 4.94s (debugger attached, not reporting)
Unable to simultaneously satisfy constraints.
    Probably at least one of the constraints in the following list is one you don't want. 
    Try this: 
        (1) look at each constraint and try to figure out which you don't expect; 
        (2) find the code that added the unwanted constraint or constraints and fix it. 
(
    "<NSLayoutConstraint:0x13204ef30 'accessoryView.bottom' _UIRemoteKeyboardPlaceholderView:0x10a02b480.bottom == _UIKBCompatInputView:0x132ff9500.top   (active)>",
    "<NSLayoutConstraint:0x126a50eb0 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x13204f890 'assistantView.bottom' SystemInputAssistantView.bottom == _UIKBCompatInputView:0x132ff9500.top   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x13204fe80 'assistantView.top' V:[_UIRemoteKeyboardPlaceholderView:0x10a02b480]-(0)-[SystemInputAssistantView]   (active, names: SystemInputAssistantView:0x1324d8000 )>"
)

Will attempt to recover by breaking constraint 
<NSLayoutConstraint:0x126a50eb0 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>

Make a symbolic breakpoint at UIViewAlertForUnsatisfiableConstraints to catch this in the debugger.
The methods in the UIConstraintBasedLayoutDebugging category on UIView listed in <UIKitCore/UIView.h> may also be helpful.
Unable to simultaneously satisfy constraints.
    Probably at least one of the constraints in the following list is one you don't want. 
    Try this: 
        (1) look at each constraint and try to figure out which you don't expect; 
        (2) find the code that added the unwanted constraint or constraints and fix it. 
(
    "<NSLayoutConstraint:0x126a51e00 'accessoryView.bottom' _UIRemoteKeyboardPlaceholderView:0x10a02b480.bottom == _UIKBCompatInputView:0x132ff9500.top   (active)>",
    "<NSLayoutConstraint:0x126a52c60 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x13204f890 'assistantView.bottom' SystemInputAssistantView.bottom == _UIKBCompatInputView:0x132ff9500.top   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x13204fe80 'assistantView.top' V:[_UIRemoteKeyboardPlaceholderView:0x10a02b480]-(0)-[SystemInputAssistantView]   (active, names: SystemInputAssistantView:0x1324d8000 )>"
)

Will attempt to recover by breaking constraint 
<NSLayoutConstraint:0x126a52c60 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>

Make a symbolic breakpoint at UIViewAlertForUnsatisfiableConstraints to catch this in the debugger.
The methods in the UIConstraintBasedLayoutDebugging category on UIView listed in <UIKitCore/UIView.h> may also be helpful.
Unable to simultaneously satisfy constraints.
    Probably at least one of the constraints in the following list is one you don't want. 
    Try this: 
        (1) look at each constraint and try to figure out which you don't expect; 
        (2) find the code that added the unwanted constraint or constraints and fix it. 
(
    "<NSLayoutConstraint:0x12b9a8f00 'accessoryView.bottom' _UIRemoteKeyboardPlaceholderView:0x132585180.bottom == _UIKBCompatInputView:0x132ff9500.top   (active)>",
    "<NSLayoutConstraint:0x12b9a92c0 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x13204f890 'assistantView.bottom' SystemInputAssistantView.bottom == _UIKBCompatInputView:0x132ff9500.top   (active, names: SystemInputAssistantView:0x1324d8000 )>",
    "<NSLayoutConstraint:0x12b9a8dc0 'assistantView.top' V:[_UIRemoteKeyboardPlaceholderView:0x132585180]-(0)-[SystemInputAssistantView]   (active, names: SystemInputAssistantView:0x1324d8000 )>"
)

Will attempt to recover by breaking constraint 
<NSLayoutConstraint:0x12b9a92c0 'assistantHeight' SystemInputAssistantView.height == 45   (active, names: SystemInputAssistantView:0x1324d8000 )>

Make a symbolic breakpoint at UIViewAlertForUnsatisfiableConstraints to catch this in the debugger.
The methods in the UIConstraintBasedLayoutDebugging category on UIView listed in <UIKitCore/UIView.h> may also be helpful.
[SUBSCRIPTION] Fetching user with ID: 1758408679311x768703316078027300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/user/1758408679311x768703316078027300
[SUBSCRIPTION] getCurrentUserCompany: No company found with ID: 1758408703226x689360897862778100
[MAIN_TAB_VIEW] onAppear - Initial user role: Optional(OPS.UserRole.admin)
[MAIN_TAB_VIEW] onAppear - Current user: Optional("John Valorant")
[MAIN_TAB_VIEW] onAppear - Tab count: 4
[SUBSCRIPTION] Fetching company with ID: 1758408703226x689360897862778100
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1758408703226x689360897862778100
[SUBSCRIPTION] getCurrentUserCompany: No company found with ID: 1758408703226x689360897862778100
Failed to locate resource named "default.csv"
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-09-20T22:51:43.232Z
[SUBSCRIPTION]   Modified Date: 2025-11-23T19:51:13.652Z
[SUBSCRIPTION]   trialStartDate: 2025-09-20T22:51:44.011Z
[SUBSCRIPTION]   trialEndDate: 2025-10-20T22:51:44.011Z
[SUBSCRIPTION]   seatGraceStartDate: 2025-10-23T19:24:05.279Z
[SUBSCRIPTION] seatedEmployees field: (
    1758408679311x768703316078027300
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "reactivatedSubscription": false,
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1758664357760x122144037595433020/valorant-logo-png_seeklogo-379976.png",
        "unit": 1,
        "taskTypes": [
            "1756427112342x728535708541648900",
            "1756427141322x654599777043087400",
            "1756427161158x802760938841964500",
            "1758671670251x102948734390763520",
            "1758671690775x946226620837920800",
            "1758671742738x408179566618345500",
            "1758671771735x776772064056967200",
            "1758672052308x803121758694801400"
        ],
        "trialStartDate": "2025-09-20T22:51:44.011Z",
        "Modified Date": "2025-11-23T19:51:13.652Z",
        "seatedEmployees": [
            "1758408679311x768703316078027300"
        ],
        "hasPrioritySupport": false,
        "companyName": "Valorant Construction",
        "subscriptionStatus": "grace",
        "dataSetupPurchased": false,
        "Slug": "valorant-construction",
        "dataSetupCompleted": false,
        "phone": "(250) 538-8994",
        "stripeCustomerId": "cus_T5l9a0196RF6EO",
        "industry": [
            "Railings"
        ],
        "registered": 100,
        "calendarEventsList": [
            "1758671629118x822587252867072000",
            "1758671818149x995477862074286100",
            "1758671827750x222160038031523840",
            "1758671831892x457329422338621440",
            "1758671835042x674988539011661800",
            "1758672070286x208170210873049100",
            "1758672100483x980712853728657400"
        ],
        "seatGraceStartDate": "2025-10-23T19:24:05.279Z",
        "officeEmail": "valorantconstruction@gmail.com",
        "admin": [
            "1758408679311x768703316078027300"
        ],
        "companyDescription": "JOINED OPS 9/20/25",
        "accountHolder": "1758408679311x768703316078027300",
        "trialEndDate": "2025-10-20T22:51:44.011Z",
        "clients": [
            "1758665151444x689266275296739300",
            "1758665173609x397376817120411650",
            "1758665195358x971440734243127300",
            "1758665240104x296267654883967000",
            "1758665266888x462381264499900400",
            "1758665285878x555539581750476800",
            "1758665310859x900124132633739300"
        ],
        "_id": "1758408703226x689360897862778100",
        "companySize": "6-10",
        "defaultProjectColor": "#e5e5e5",
        "companyAge": "2-5",
        "location": {
            "address": "625 8th Ave, New York, NY 10109, USA",
            "lat": 40.756612,
            "lng": -73.9912143
        },
        "hasWebsite": true,
        "subscriptionIds": [
            "1758489979464x728104625593450900",
            "1758507295094x628786841010475760",
            "1758562119318x691320121727884800",
            "1758565111818x497436680856930600",
            "1758565281561x408900785269896700",
            "1758566528696x819170926052941100",
    ...
[CompanyDTO] Decoded seatGraceStartDate as ISO8601 string: 2025-10-23T19:24:05.279Z -> 2025-10-23 19:24:05 +0000
[CompanyDTO] Decoded trialStartDate as ISO8601 string: 2025-09-20T22:51:44.011Z -> 2025-09-20 22:51:44 +0000
[CompanyDTO] Decoded trialEndDate as ISO8601 string: 2025-10-20T22:51:44.011Z -> 2025-10-20 22:51:44 +0000
[CompanyDTO] Successfully decoded company with ID: 1758408703226x689360897862778100
[SUBSCRIPTION] Admin IDs: 1 admins
[SUBSCRIPTION] From Bubble: Status=grace -> grace
[SUBSCRIPTION] From Bubble: Plan=business -> business
[SUBSCRIPTION] From Bubble: Seats=1/10
[SUBSCRIPTION] 🔍 Processing seated employees: 1 refs
[SUBSCRIPTION] 🔍 Extracted 1 seated IDs: ["1758408679311x768703316078027300"]
[SUBSCRIPTION] ✅ Set seated employees on company: ["1758408679311x768703316078027300"]
[SYNC_TEAM_MEMBERS] 🔄 Syncing team members for company 1758408703226x689360897862778100
[API_ERROR] HTTP 404 - Response body: {
  "page_name": "404",
  "assets": {
    "css": [
      "/package/run_css/48c644ef145e93b4b1bdd507ddb6a7f94103bbf42b3c8540979879e3e3a5e796/canprojack/live/404/xfalse/xfalse/run.css"
    ],
    "js": [
      "/package/global_js/ab4d5c918fe3321850aaa6a574bb726aad5b7bf345b696d1007053bb70dddd32/canprojack/live/404/xnull/xfalse/xtrue/en_us/xfalse/xfalse/global.js",
      "/package/page_js/d468685b347e872f7a8748f1ffeebd0e8b588b5636c7d01e9714480bf815a868/canprojack/live/404/xtrue/en_us/page.js"
    ]
  },
  "metadata": {
    "title": "404 ERROR | Ops",
    "description": "Finally, job management that works offline and doesn't waste your time. Built by tradesmen who got tired of apps that don't understand the field.",
    "favicon": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1738782679635x718290702620368400/Ops%20Logo%20White.png"
  },
  "headers": {
    "custom_app_header": "<!-- custom app meta header -->\n<link rel=\"preload\" href=\"https://fonts.googleapis.com/css2?family=Bebas+Neue&display=swap\" as=\"style\" onload=\"this.onload=null;this.rel='stylesheet'\">\n<noscript><link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Bebas+Neue&display=swap\"></noscript>\n\n<link rel=\"preload\" href=\"https://fonts.googleapis.com/css2?family=Kosugi&display=swap\" as=\"style\" onload=\"this.onload=null;this.rel='stylesheet'\">\n<noscript><link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Kosugi&display=swap\"></noscript>\n\n\n\n\n<!-- Google Tag Manager -->\n<script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':\nnew Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],\nj=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=\n'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);\n})(window,document,'script','dataLayer','GTM-5VM9DNQM');</script>\n<!-- End Google Tag Manager -->",
    "custom_body_script": "<!-- Google Tag Manager (noscript) -->\n<noscript><iframe src=\"https://www.googletagmanager.com/ns.html?id=GTM-5VM9DNQM\"\nheight=\"0\" width=\"0\" style=\"display:none;visibility:hidden\"></iframe></noscript>\n<!-- End Google Tag Manager (noscript) -->",
    "seo_headers": [
      "<meta property=\"og:title\" content=\"OPS: Job Management Built by Trades, for Trades\" />",
      "<meta name=\"twitter:title\" content=\"OPS: Job Management Built by Trades, for Trades\" />",
      "<meta property=\"og:site_name\" content=\"OPS\" />",
      "<meta name=\"twitter:site_name\" content=\"OPS\" />",
      "<meta property=\"og:description\" content=\"Finally, job management that works offline and doesn&#39;t waste your time. Built by tradesmen who got tired of apps that don&#39;t understand the field.\" />",
      "<meta name=\"twitter:description\" content=\"Finally, job management that works offline and doesn&#39;t waste your time. Built by tradesmen who got tired of apps that don&#39;t understand the field.\" />",
      "<link rel=\"image_src\" href=\"https://21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/cdn-cgi/image/w=,h=,f=auto,dpr=1,fit=contain/f1757967555831x673765443826645100/Ops%20Logo%20Alert%20Color.png\" />",
      "<meta property=\"og:image\" content=\"https://21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/cdn-cgi/image/w=,h=,f=auto,dpr=1,fit=contain/f1757967555831x673765443826645100/Ops%20Logo%20Alert%20Color.png\" />",
      "<meta name=\"twitter:image:src\" content=\"https://21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/cdn-cgi/image/w=,h=,f=auto,dpr=1,fit=contain/f1757967555831x673765443826645100/Ops%20Logo%20Alert%20Color.png\" />",
      "<meta property=\"og:url\" content=\"https://opsapp.co/obj/opscontacts\" />",
      "<meta property=\"og:type\" content=\"website\" />"
    ],
    "basic_headers": [
      "<meta name=\"twitter:card\" content=\"summary_large_image\" />",
      "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\">",
      "<meta name=\"apple-mobile-web-app-status-bar-style\" content=\"black-translucent\" />",
      "<link rel=\"apple-touch-icon\" href=\"https://21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/cdn-cgi/image/w=192,h=,f=auto,dpr=1,fit=contain/f1738782661820x178701969113171500/Ops%20Logo%20black%20background.png\">",
      "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1.0\">"
    ],
    "plugin_app_headers": [
      {
        "plugin_id": "1499780054879x111265002286743550",
        "header": "<!-- 1499780054879x111265002286743550 -->\n<script id=\"apexcharts\" src=\"https://cdnjs.cloudflare.com/ajax/libs/apexcharts/3.37.3/apexcharts.min.js\"></script>"
      },
      {
        "plugin_id": "1580238841425x582072028873097200",
        "header": "<!-- 1580238841425x582072028873097200 -->\n<style>\n    \n    blockquote {\n        border-left: 4px solid #ccc;\n   \t\tmargin-bottom: 5px;\n    \tmargin-top: 5px;\n        padding-left: 16px;\n    }\n    \n    ul, ol {\n    \tlist-style-position: outside;\n    }\n    \n    .ql-font .ql-picker-label:first-child::before {\n    \tfont-family: inherit;    \n        overflow: hide;\n    }\n    \n    .ql-font .ql-picker-label {\n        overflow: hidden;\n    }\n    \n    .regular-header-icon {\n        color: #444;\n    }\n    \n    .tooltip-header-icon {\n        color: #ccc;\n    }\n    \n</style>"
      },
      {
        "plugin_id": "1727363209115x976445017742639100",
        "header": "<!-- 1727363209115x976445017742639100 -->\n<style>\n\n.ionic-toggle.toggle-balanced{\ntransform: scale() !important;\n}\n\n.ionic-handle  {\nheight: 23px !important;\nwidth: 23px !important;\ntop: 9px !important;\nleft: 10px !important;\nbox-shadow: 0 2px 7px rgba(0, 0, 0, 0.15), 0 1px 1px rgba(0, 0, 0, 0.15) !important;\nbackground-color:  !important;\n}\n\n.ionic-toggle .ionic-track {\nbackground-color:  !important;\nborder-color:  !important;\n}\n    \n.ionic-toggle.toggle-balanced input:checked + .ionic-track {\nbackground-color:  !important;\nborder-color:  !important;\n\n}\n\n.ionic-toggle input:disabled + .ionic-track {\nopacity:  !important;\n}\n    \n</style>"
      }
    ],
    "plugin_page_headers": []
  },
  "errors": []
}
[LOGIN] 🔄 Starting full sync after login...
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION CALLED
[SYNC_ALL] ========================================
[SYNC_ALL] 🔄 FULL SYNC STARTED
[SYNC_ALL] ========================================
[SYNC_ALL] Starting complete data sync...
[SYNC_DEBUG] [syncAll()] 📊 Starting complete data sync
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA BEFORE SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 1
[SYNC_DEBUG] [syncAll()]   - Clients: 0
[SYNC_DEBUG] [syncAll()]   - Task Types: 0
[SYNC_DEBUG] [syncAll()]   - Projects: 0
[SYNC_DEBUG] [syncAll()]   - Tasks: 0
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 0
[SYNC_DEBUG] [syncAll()] → Syncing Company...
[SYNC_DEBUG] [syncCompany()] 🔵 FUNCTION CALLED
[SYNC_COMPANY] 📊 Syncing company data...
[SYNC_DEBUG] [syncCompany()] 📥 Fetching company from API with ID: 1758408703226x689360897862778100
[SUBSCRIPTION] Fetching company with ID: 1758408703226x689360897862778100
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1758408703226x689360897862778100
[SYNC_TEAM_MEMBERS] ✅ Synced 4 team members
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-09-20T22:51:43.232Z
[SUBSCRIPTION]   Modified Date: 2025-11-23T19:51:13.652Z
[SUBSCRIPTION]   trialStartDate: 2025-09-20T22:51:44.011Z
[SUBSCRIPTION]   trialEndDate: 2025-10-20T22:51:44.011Z
[SUBSCRIPTION]   seatGraceStartDate: 2025-10-23T19:24:05.279Z
[SUBSCRIPTION] seatedEmployees field: (
    1758408679311x768703316078027300
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "reactivatedSubscription": false,
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1758664357760x122144037595433020/valorant-logo-png_seeklogo-379976.png",
        "unit": 1,
        "taskTypes": [
            "1756427112342x728535708541648900",
            "1756427141322x654599777043087400",
            "1756427161158x802760938841964500",
            "1758671670251x102948734390763520",
            "1758671690775x946226620837920800",
            "1758671742738x408179566618345500",
            "1758671771735x776772064056967200",
            "1758672052308x803121758694801400"
        ],
        "trialStartDate": "2025-09-20T22:51:44.011Z",
        "Modified Date": "2025-11-23T19:51:13.652Z",
        "seatedEmployees": [
            "1758408679311x768703316078027300"
        ],
        "hasPrioritySupport": false,
        "companyName": "Valorant Construction",
        "subscriptionStatus": "grace",
        "dataSetupPurchased": false,
        "Slug": "valorant-construction",
        "dataSetupCompleted": false,
        "phone": "(250) 538-8994",
        "stripeCustomerId": "cus_T5l9a0196RF6EO",
        "industry": [
            "Railings"
        ],
        "registered": 100,
        "calendarEventsList": [
            "1758671629118x822587252867072000",
            "1758671818149x995477862074286100",
            "1758671827750x222160038031523840",
            "1758671831892x457329422338621440",
            "1758671835042x674988539011661800",
            "1758672070286x208170210873049100",
            "1758672100483x980712853728657400"
        ],
        "seatGraceStartDate": "2025-10-23T19:24:05.279Z",
        "officeEmail": "valorantconstruction@gmail.com",
        "admin": [
            "1758408679311x768703316078027300"
        ],
        "companyDescription": "JOINED OPS 9/20/25",
        "accountHolder": "1758408679311x768703316078027300",
        "trialEndDate": "2025-10-20T22:51:44.011Z",
        "clients": [
            "1758665151444x689266275296739300",
            "1758665173609x397376817120411650",
            "1758665195358x971440734243127300",
            "1758665240104x296267654883967000",
            "1758665266888x462381264499900400",
            "1758665285878x555539581750476800",
            "1758665310859x900124132633739300"
        ],
        "_id": "1758408703226x689360897862778100",
        "companySize": "6-10",
        "defaultProjectColor": "#e5e5e5",
        "companyAge": "2-5",
        "location": {
            "address": "625 8th Ave, New York, NY 10109, USA",
            "lat": 40.756612,
            "lng": -73.9912143
        },
        "hasWebsite": true,
        "subscriptionIds": [
            "1758489979464x728104625593450900",
            "1758507295094x628786841010475760",
            "1758562119318x691320121727884800",
            "1758565111818x497436680856930600",
            "1758565281561x408900785269896700",
            "1758566528696x819170926052941100",
    ...
[CompanyDTO] Decoded seatGraceStartDate as ISO8601 string: 2025-10-23T19:24:05.279Z -> 2025-10-23 19:24:05 +0000
[CompanyDTO] Decoded trialStartDate as ISO8601 string: 2025-09-20T22:51:44.011Z -> 2025-09-20 22:51:44 +0000
[CompanyDTO] Decoded trialEndDate as ISO8601 string: 2025-10-20T22:51:44.011Z -> 2025-10-20 22:51:44 +0000
[CompanyDTO] Successfully decoded company with ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncCompany()] ✅ API returned company DTO
[SYNC_DEBUG] [syncCompany()]   - ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncCompany()]   - Name: Valorant Construction
[SYNC_DEBUG] [syncCompany()]   - Plan: business
[SYNC_DEBUG] [syncCompany()]   - Status: grace
[SYNC_DEBUG] [syncCompany()] 🔍 Finding or creating local company record
[SYNC_DEBUG] [syncCompany()] ✅ Local company record ready: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncCompany()] 📝 Updating company properties...
[SYNC_COMPANY] 💺 Set 1 seated employees
[SYNC_DEBUG] [syncCompany()] 💾 Saving company to modelContext...
[SYNC_DEBUG] [syncCompany()] ✅ Company saved successfully
[SYNC_COMPANY] ✅ Company synced
[SYNC_DEBUG] [syncAll()] → Syncing Users...
[SYNC_DEBUG] [syncUsers()] 🔵 FUNCTION CALLED
[SYNC_USERS] 👥 Syncing users...
[SYNC_DEBUG] [syncUsers()] 📥 Fetching users from API for company: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB BEFORE sync: 4
[SYNC_DEBUG] [syncUsers()] 👑 Company has 1 admin IDs: ["1758408679311x768703316078027300"]
[SYNC_DEBUG] [syncUsers()] ✅ API returned 4 user DTOs
[SYNC_DEBUG] [syncUsers()]   - User: John Valorant (ID: 1758408679311x768703316078027300, Role: Admin)
[SYNC_DEBUG] [syncUsers()]   - User: Jason Bourne (ID: 1758664435120x907873718703669000, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Daniel Davis (ID: 1758664885005x312641150642454200, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Richard Peterson (ID: 1758664942860x330544742077434400, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()] 🔍 Handling deletions - remote IDs count: 4
[SYNC_DEBUG] [syncUsers()] 📝 Upserting 4 users...
[SYNC_DEBUG] [syncUsers()]   [1/4] Processing user: John Valorant
[SYNC_DEBUG] [syncUsers()]     - 👑 Role set to ADMIN (in company.adminIds)
[SYNC_DEBUG] [syncUsers()]   [2/4] Processing user: Jason Bourne
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [3/4] Processing user: Daniel Davis
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [4/4] Processing user: Richard Peterson
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()] 💾 Saving 4 users to modelContext...
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB AFTER sync: 4
[SYNC_DEBUG] [syncUsers()] ✅ Users synced successfully
[SYNC_USERS] ✅ Synced 4 users
[SYNC_DEBUG] [syncAll()] → Syncing Clients...
[SYNC_CLIENTS] 🏢 Syncing clients...
[SYNC_CLIENTS] ✅ Synced 7 clients
[SYNC_DEBUG] [syncAll()] → Syncing Task Types...
[SYNC_TASK_TYPES] 🏷️ Syncing task types...
[SUBSCRIPTION] Fetching company with ID: 1758408703226x689360897862778100
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1758408703226x689360897862778100
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-09-20T22:51:43.232Z
[SUBSCRIPTION]   Modified Date: 2025-11-23T19:51:13.652Z
[SUBSCRIPTION]   trialStartDate: 2025-09-20T22:51:44.011Z
[SUBSCRIPTION]   trialEndDate: 2025-10-20T22:51:44.011Z
[SUBSCRIPTION]   seatGraceStartDate: 2025-10-23T19:24:05.279Z
[SUBSCRIPTION] seatedEmployees field: (
    1758408679311x768703316078027300
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "reactivatedSubscription": false,
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1758664357760x122144037595433020/valorant-logo-png_seeklogo-379976.png",
        "unit": 1,
        "taskTypes": [
            "1756427112342x728535708541648900",
            "1756427141322x654599777043087400",
            "1756427161158x802760938841964500",
            "1758671670251x102948734390763520",
            "1758671690775x946226620837920800",
            "1758671742738x408179566618345500",
            "1758671771735x776772064056967200",
            "1758672052308x803121758694801400"
        ],
        "trialStartDate": "2025-09-20T22:51:44.011Z",
        "Modified Date": "2025-11-23T19:51:13.652Z",
        "seatedEmployees": [
            "1758408679311x768703316078027300"
        ],
        "hasPrioritySupport": false,
        "companyName": "Valorant Construction",
        "subscriptionStatus": "grace",
        "dataSetupPurchased": false,
        "Slug": "valorant-construction",
        "dataSetupCompleted": false,
        "phone": "(250) 538-8994",
        "stripeCustomerId": "cus_T5l9a0196RF6EO",
        "industry": [
            "Railings"
        ],
        "registered": 100,
        "calendarEventsList": [
            "1758671629118x822587252867072000",
            "1758671818149x995477862074286100",
            "1758671827750x222160038031523840",
            "1758671831892x457329422338621440",
            "1758671835042x674988539011661800",
            "1758672070286x208170210873049100",
            "1758672100483x980712853728657400"
        ],
        "seatGraceStartDate": "2025-10-23T19:24:05.279Z",
        "officeEmail": "valorantconstruction@gmail.com",
        "admin": [
            "1758408679311x768703316078027300"
        ],
        "companyDescription": "JOINED OPS 9/20/25",
        "accountHolder": "1758408679311x768703316078027300",
        "trialEndDate": "2025-10-20T22:51:44.011Z",
        "clients": [
            "1758665151444x689266275296739300",
            "1758665173609x397376817120411650",
            "1758665195358x971440734243127300",
            "1758665240104x296267654883967000",
            "1758665266888x462381264499900400",
            "1758665285878x555539581750476800",
            "1758665310859x900124132633739300"
        ],
        "_id": "1758408703226x689360897862778100",
        "companySize": "6-10",
        "defaultProjectColor": "#e5e5e5",
        "companyAge": "2-5",
        "location": {
            "address": "625 8th Ave, New York, NY 10109, USA",
            "lat": 40.756612,
            "lng": -73.9912143
        },
        "hasWebsite": true,
        "subscriptionIds": [
            "1758489979464x728104625593450900",
            "1758507295094x628786841010475760",
            "1758562119318x691320121727884800",
            "1758565111818x497436680856930600",
            "1758565281561x408900785269896700",
            "1758566528696x819170926052941100",
    ...
[CompanyDTO] Decoded seatGraceStartDate as ISO8601 string: 2025-10-23T19:24:05.279Z -> 2025-10-23 19:24:05 +0000
[CompanyDTO] Decoded trialStartDate as ISO8601 string: 2025-09-20T22:51:44.011Z -> 2025-09-20 22:51:44 +0000
[CompanyDTO] Decoded trialEndDate as ISO8601 string: 2025-10-20T22:51:44.011Z -> 2025-10-20 22:51:44 +0000
[CompanyDTO] Successfully decoded company with ID: 1758408703226x689360897862778100
[SYNC_TASK_TYPES] ✅ Synced 8 task types
[SYNC_DEBUG] [syncAll()] → Syncing Projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: nil)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1758408679311x768703316078027300, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 0
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1758408703226x689360897862778100
[PAGINATION] 📊 Starting paginated fetch for Project
[PAGINATION] 📄 Page 1: Fetched 10 Projects (Total: 10)
[PAGINATION] ✅ Completed: Total 10 Projects fetched across 1 page(s)
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 10 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 10 project DTOs
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Install (ID: 1758665932250x777755282018140200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Picket Railings (ID: 1758666277192x442590516801962000, Status: Closed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Railings (ID: 1758666252706x826417154340945900, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Rail Install (ID: 1758666182742x130832992535838720, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Project (ID: 1758671620469x205868104802369540, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Deck Build (ID: 1758666197934x427914661396217860, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: VInyl Installation (ID: 1758665876803x111531651910074370, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl Installation (ID: 1758666129631x797416361305309200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation (ID: 1758666089995x735505024600506400, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Vinyl and Rail (ID: 1758666174622x785516955462795300, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1758666129631x797416361305309200, 1758666089995x735505024600506400, 1758671620469x205868104802369540, 1758665876803x111531651910074370, 1758666197934x427914661396217860, 1758666252706x826417154340945900, 1758666182742x130832992535838720, 1758666174622x785516955462795300, 1758665932250x777755282018140200, 1758666277192x442590516801962000
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 10
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1758666129631x797416361305309200, 1758666089995x735505024600506400, 1758671620469x205868104802369540, 1758665876803x111531651910074370, 1758666197934x427914661396217860, 1758666252706x826417154340945900, 1758666182742x130832992535838720, 1758666174622x785516955462795300, 1758665932250x777755282018140200, 1758666277192x442590516801962000
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 0
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 0
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 10 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/10] Processing project: Vinyl Install (ID: 1758665932250x777755282018140200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665285878x555539581750476800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/10] Processing project: Picket Railings (ID: 1758666277192x442590516801962000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665266888x462381264499900400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/10] Processing project: Glass Railings (ID: 1758666252706x826417154340945900)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665266888x462381264499900400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/10] Processing project: Glass Rail Install (ID: 1758666182742x130832992535838720)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665173609x397376817120411650
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/10] Processing project: Deck Project (ID: 1758671620469x205868104802369540)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665266888x462381264499900400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/10] Processing project: Composite Deck Build (ID: 1758666197934x427914661396217860)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665151444x689266275296739300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 5
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/10] Processing project: VInyl Installation (ID: 1758665876803x111531651910074370)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665310859x900124132633739300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/10] Processing project: Vinyl Installation (ID: 1758666129631x797416361305309200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665240104x296267654883967000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/10] Processing project: Deck Renovation (ID: 1758666089995x735505024600506400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665266888x462381264499900400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/10] Processing project: Vinyl and Rail (ID: 1758666174622x785516955462795300)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1758408703226x689360897862778100
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1758665195358x971440734243127300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 10 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 10
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 10 projects
[SYNC_DEBUG] [syncAll()] → Syncing Tasks...
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[PAGINATION] 📄 Page 1: Fetched 7 Tasks (Total: 7)
[PAGINATION] ✅ Completed: Total 7 Tasks fetched across 1 page(s)
[SYNC_TASKS] ✅ Synced 7 tasks
[SYNC_DEBUG] [syncAll()] → Syncing Calendar Events...
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[PAGINATION] 📄 Page 1: Fetched 7 calendarevents (Total: 7)
[PAGINATION] ✅ Completed: Total 7 calendarevents fetched across 1 page(s)
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS INSTALLATION' color from API: #5e8eb3
[SYNC_CALENDAR] 🎨 Setting task event 'GENERAL WORK' color from API: #d1938b
[SYNC_CALENDAR] 🎨 Setting task event 'FRAMING' color from API: #dca96d
[SYNC_CALENDAR] 🎨 Setting task event 'COMPOSITE DECKING INSTALL' color from API: #806a4e
[SYNC_CALENDAR] 🎨 Setting task event 'VINYL INSTALL' color from API: #bf92c8
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS INSTALLATION' color from API: #5e8eb3
[SYNC_CALENDAR] 🎨 Setting task event 'GLASS PANEL INSTALLATION' color from API: #b6d6de
[SYNC_CALENDAR] ✅ Synced 7 calendar events
[SYNC_DEBUG] [syncAll()] → Linking Relationships...
[LINK_RELATIONSHIPS] 🔗 Linking all relationships...
CoreData: debug: PostSaveMaintenance: incremental_vacuum with freelist_count - 51 and pages_to_free 10
[LINK_RELATIONSHIPS] ✅ Linked 69 relationships
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA AFTER SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 4
[SYNC_DEBUG] [syncAll()]   - Clients: 7
[SYNC_DEBUG] [syncAll()]   - Task Types: 8
[SYNC_DEBUG] [syncAll()]   - Projects: 10
[SYNC_DEBUG] [syncAll()]   - Tasks: 7
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 7
[SYNC_DEBUG] [syncAll()] ✅ Complete sync finished successfully at 2025-11-23 19:58:16 +0000
[SYNC_ALL] ✅ Complete sync finished
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION EXITING - syncInProgress set to false
[SYNC_ALL] ========================================
[SYNC_ALL] 🏁 FULL SYNC COMPLETED
[SYNC_ALL] ========================================
[LOGIN] ✅ Full sync completed successfully
[HOME] 🔄 Initial sync completed, reloading today's projects
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: grace, Plan: business, Seats: 1/10
[SUBSCRIPTION] User admin check: true (user: 1758408679311x768703316078027300, admins: 1)
[AUTH] ✅ Access granted - grace subscription with seat
[AUTH] ✅ All 5 validation layers passed
[APP_ACTIVE] 🏥 App became active - checking data health...
[DATA_HEALTH] 🔎 Checking for minimum required data...
[DATA_HEALTH] ✅ Minimum required data present
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: grace, Plan: business, Seats: 1/10
[SUBSCRIPTION] User admin check: true (user: 1758408679311x768703316078027300, admins: 1)
[AUTH] ✅ Access granted - grace subscription with seat
[AUTH] ✅ All 5 validation layers passed
Swift/arm64e-apple-ios.swiftinterface:6974: Fatal error: Range requires lowerBound <= upperBound
Swift/arm64e-apple-ios.swiftinterface:6974: Fatal error: Range requires lowerBound <= upperBound
