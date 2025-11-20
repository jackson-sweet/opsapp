[SYNC] 📱 Initial connection state: Connected
[APP_LAUNCH] 🏥 Performing data health check before app launch sync...
[APP_LAUNCH] ✅ User authenticated with ID: 1749432802202x703263025035244900
[DATA_HEALTH] 🏥 Performing comprehensive health check...
[DATA_HEALTH] ✅ User ID exists: 1749432802202x703263025035244900
[DATA_HEALTH] ✅ Current user exists: Test User
[DATA_HEALTH] ✅ Company ID exists: 1749432890812x563585058122141300
[DATA_HEALTH] ✅ Company data exists
[DATA_HEALTH] ✅ SyncManager initialized
[DATA_HEALTH] ✅ ModelContext available
[DATA_HEALTH] ✅ All health checks passed - data is healthy
[APP_LAUNCH] ✅ Data health check passed
[APP_LAUNCH] 🔄 Proceeding with full sync and subscription check
[APP_LAUNCH_SYNC] 🚀 Starting app launch sync
[APP_LAUNCH_SYNC] - isConnected: true
[APP_LAUNCH_SYNC] - isAuthenticated: true
[APP_LAUNCH_SYNC] - currentUser: Test User
[APP_LAUNCH_SYNC] - syncManager: available
[APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)
[SYNC] 🔌 Network state changed: Connected
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 5/10
[SUBSCRIPTION] User admin check: true (user: 1749432802202x703263025035244900, admins: 1)
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: true)
[APP_ACTIVE] 🏥 App became active - checking data health...
[APP_LAUNCH_SYNC] ✅ Full sync completed
[DATA_HEALTH] 🔎 Checking for minimum required data...
[DATA_HEALTH] ✅ Minimum required data present
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 5/10
[SUBSCRIPTION] User admin check: true (user: 1749432802202x703263025035244900, admins: 1)
[AUTH] ✅ Access granted - active subscription with seat
[AUTH] ✅ All 5 validation layers passed
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] Current state - Status: active, Plan: business, Seats: 5/10
[SUBSCRIPTION] User admin check: true (user: 1749432802202x703263025035244900, admins: 1)
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
[SYNC_DEBUG] [syncAll()]   - Users: 4
[SYNC_DEBUG] [syncAll()]   - Clients: 13
[SYNC_DEBUG] [syncAll()]   - Task Types: 5
[SYNC_DEBUG] [syncAll()]   - Projects: 35
[SYNC_DEBUG] [syncAll()]   - Tasks: 52
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 39
[SYNC_DEBUG] [syncAll()] → Syncing Company...
[SYNC_DEBUG] [syncCompany()] 🔵 FUNCTION CALLED
[SYNC_COMPANY] 📊 Syncing company data...
[SYNC_DEBUG] [syncCompany()] 📥 Fetching company from API with ID: 1749432890812x563585058122141300
[SUBSCRIPTION] Fetching company with ID: 1749432890812x563585058122141300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1749432890812x563585058122141300
[TRIGGER_BG_SYNC] ✅ Starting background refresh
[SYNC_BG] 🔄 Background refresh...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: 2025-11-20 20:58:03 +0000)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1749432802202x703263025035244900, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1749432890812x563585058122141300
[PAGINATION] 📊 Starting paginated fetch for Project
[PAGINATION] 📄 Page 1: Fetched 35 Projects (Total: 35)
[PAGINATION] ✅ Completed: Total 35 Projects fetched across 1 page(s)
[MAIN_TAB_VIEW] onAppear - Initial user role: Optional(OPS.UserRole.admin)
[MAIN_TAB_VIEW] onAppear - Current user: Optional("Test User")
[MAIN_TAB_VIEW] onAppear - Tab count: 4
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 35 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 35 project DTOs
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Decking Renovation (ID: 1749433560900x375570893353779200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Citygate Boulevard (ID: 1760052988218x653265573877647400, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Installation (ID: 1749433525330x509910274265841660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project Jacob (ID: 1760553485041x328848046193623840, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Rowhomes Project (ID: 1761267917908x754340491805805000, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Blanshard Renovation (ID: 1760551329635x214462564021837150, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749433514282x402143493015994400, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Project Deck Renovation (ID: 1761278507610x624717899061788700, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Railings Installation (ID: 1749433544398x644658077188227100, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Pergola Framing (ID: 1749433567369x519244473119539200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project (ID: 1761156833428x451468226316574340, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project New (ID: 1761162539485x177948205785155600, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project OCTOBER 22 (ID: 1761161046758x931633369376104700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Next Test Project (ID: 1761174462261x646789331060738700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Photo Project (ID: 1761268217255x190256784716349660, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test project  TEST 4 (ID: 1761161518256x140411073446936370, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings & Vinyl (ID: 1761759177820x920922776128854000, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test project 11/16 (ID: 1763363102567x223600379296342370, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1760052837877x111242630189534200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1760053040074x897191029414202200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: James Bay Residences (ID: 1760053708654x396262514789569100, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Landsdowne Renovation (ID: 1760553017732x459643017552842100, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 5 (ID: 1760553057960x848788932669397600, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Project Based Test (ID: 1761172478275x262746266349336740, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project Pete (ID: 1761173859745x700938540474596500, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Trst reno (ID: 1761173971446x462788748593081500, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation/Reconstruction (ID: 1761181464028x514567553211649600, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 2-11/16 (ID: 1763364286137x710011798596255100, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Clean slate test Project (ID: 1763403975497x994358677235182700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 11/18 (ID: 1763509969216x863800873848467500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 0827 (ID: 1763526474110x984724149515322200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 1119.1 (ID: 1763578403953x524310636951218940, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 1119.2 (ID: 1763578908485x147354716986443740, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 11/19.2 (ID: 1763609021721x425734433842798200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement (ID: 1763661342904x581637806788413800, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1763509969216x863800873848467500, 1763578908485x147354716986443740, 1763609021721x425734433842798200, 1760053040074x897191029414202200, 1761278507610x624717899061788700, 1749433514282x402143493015994400, 1761268217255x190256784716349660, 1761173859745x700938540474596500, 1761173971446x462788748593081500, 1761172478275x262746266349336740...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 35
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1763509969216x863800873848467500, 1763578908485x147354716986443740, 1763609021721x425734433842798200, 1760053040074x897191029414202200, 1761278507610x624717899061788700, 1749433514282x402143493015994400, 1761268217255x190256784716349660, 1761173859745x700938540474596500, 1761173971446x462788748593081500, 1761172478275x262746266349336740...
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-06-09T01:34:50.822Z
[SUBSCRIPTION]   Modified Date: 2025-11-20T17:55:43.462Z
[SUBSCRIPTION] seatedEmployees field: (
    1750977599033x353965879696517500,
    1760052300279x108662282911617730,
    1749432802202x703263025035244900,
    1760051201910x723551976281209700,
    1760052397233x324423650406588740
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1760052614190x555463743569300400/channels4_profile.avif",
        "clients": [
            "1749433390580x459430916087611400",
            "1749433416591x491305525683159040",
            "1749433453320x656056024164728800",
            "1749433475674x137708773356601340",
            "1749433506218x593920412915335200",
            "1760553457890x454432096959072060",
            "1761181441307x489756751367648200",
            "1761759155434x159074945739295040",
            "1763509025227x692852893963504100",
            "1763661246094x959999678947481000"
        ],
        "qbConnected": false,
        "projects": [
            "1749433514282x402143493015994400",
            "1749433525330x509910274265841660",
            "1749433544398x644658077188227100",
            "1749433560900x375570893353779200",
            "1749433567369x519244473119539200",
            "1760551329635x214462564021837150",
            "1760553017732x459643017552842100",
            "1760553057960x848788932669397600",
            "1760553485041x328848046193623840",
            "1760053040074x897191029414202200",
            "1761156833428x451468226316574340",
            "1761161046758x931633369376104700",
            "1761162539485x177948205785155600",
            "1761172478275x262746266349336740",
            "1761173971446x462788748593081500",
            "1761174462261x646789331060738700",
            "1761181464028x514567553211649600",
            "1761267917908x754340491805805000",
            "1761268217255x190256784716349660",
            "1761278507610x624717899061788700",
            "1761759177820x920922776128854000",
            "1763363102567x223600379296342370",
            "1763364286137x710011798596255100",
            "1763403975497x994358677235182700",
            "1763509969216x863800873848467500",
            "1763526474110x984724149515322200",
            "1763578403953x524310636951218940",
            "1763578908485x147354716986443740",
            "1763609021721x425734433842798200",
            "1763661342904x581637806788413800"
        ],
        "registered": 100,
        "companyId": "1749432890812x563585058122141300",
        "employees": [
            "1749432802202x703263025035244900",
            "1760051201910x723551976281209700",
            "1760052300279x108662282911617730",
            "1760052397233x324423650406588740"
        ],
        "Created Date": "2025-06-09T01:34:50.822Z",
        "location": {
            "address": "1200 Fort St, Victoria, BC V8V, Canada",
            "lat": 48.4229532,
            "lng": -123.3498386
        },
        "companyAge": "5-10",
        "phone": "2588943323",
        "companySize": "3-5",
        "openHour": "08:00:00",
        "maxSeats": 10,
        "_id": "1749432890812x563585058122141300",
        "closeHour": "17:00:00",
        "subscriptionStatus": "active",
        "Slug": "test-company",
        "industry...
[CompanyDTO] Successfully decoded company with ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 35
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 35 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/35] Processing project: Composite Decking Renovation (ID: 1749433560900x375570893353779200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433416591x491305525683159040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/35] Processing project: Citygate Boulevard (ID: 1760052988218x653265573877647400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/35] Processing project: Railings Installation (ID: 1749433525330x509910274265841660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/35] Processing project: Test Project Jacob (ID: 1760553485041x328848046193623840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760553457890x454432096959072060
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/35] Processing project: Rowhomes Project (ID: 1761267917908x754340491805805000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/35] Processing project: Blanshard Renovation (ID: 1760551329635x214462564021837150)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/35] Processing project: Deck Reconstruction (ID: 1749433514282x402143493015994400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433416591x491305525683159040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/35] Processing project: Project Deck Renovation (ID: 1761278507610x624717899061788700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/35] Processing project: Glass Railings Installation (ID: 1749433544398x644658077188227100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/35] Processing project: Pergola Framing (ID: 1749433567369x519244473119539200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/35] Processing project: Test Project (ID: 1761156833428x451468226316574340)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/35] Processing project: Test Project New (ID: 1761162539485x177948205785155600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/35] Processing project: Test Project OCTOBER 22 (ID: 1761161046758x931633369376104700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/35] Processing project: Next Test Project (ID: 1761174462261x646789331060738700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/35] Processing project: Photo Project (ID: 1761268217255x190256784716349660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/35] Processing project: Test project  TEST 4 (ID: 1761161518256x140411073446936370)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760553457890x454432096959072060
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/35] Processing project: Railings & Vinyl (ID: 1761759177820x920922776128854000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/35] Processing project: Test project 11/16 (ID: 1763363102567x223600379296342370)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/35] Processing project: Railings (ID: 1760052837877x111242630189534200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/35] Processing project: Deck Reconstruction (ID: 1760053040074x897191029414202200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760053009663x246333797400918530
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/35] Processing project: James Bay Residences (ID: 1760053708654x396262514789569100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/35] Processing project: Landsdowne Renovation (ID: 1760553017732x459643017552842100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/35] Processing project: Test Project 5 (ID: 1760553057960x848788932669397600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/35] Processing project: Project Based Test (ID: 1761172478275x262746266349336740)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/35] Processing project: Test Project Pete (ID: 1761173859745x700938540474596500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/35] Processing project: Trst reno (ID: 1761173971446x462788748593081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/35] Processing project: Deck Renovation/Reconstruction (ID: 1761181464028x514567553211649600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761181441307x489756751367648200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/35] Processing project: Test Project 2-11/16 (ID: 1763364286137x710011798596255100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/35] Processing project: Clean slate test Project (ID: 1763403975497x994358677235182700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/35] Processing project: Test Project 11/18 (ID: 1763509969216x863800873848467500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/35] Processing project: Test Project 0827 (ID: 1763526474110x984724149515322200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/35] Processing project: Test Project 1119.1 (ID: 1763578403953x524310636951218940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/35] Processing project: Test Project 1119.2 (ID: 1763578908485x147354716986443740)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/35] Processing project: Test Project 11/19.2 (ID: 1763609021721x425734433842798200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/35] Processing project: Tek Screw Replacement (ID: 1763661342904x581637806788413800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661246094x959999678947481000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 35 projects to modelContext...
CoreData: debug: PostSaveMaintenance: incremental_vacuum with freelist_count - 36 and pages_to_free 7
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 35 projects
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[SYNC_DEBUG] [syncCompany()] ✅ API returned company DTO
[SYNC_DEBUG] [syncCompany()]   - ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncCompany()]   - Name: Test Company
[SYNC_DEBUG] [syncCompany()]   - Plan: business
[SYNC_DEBUG] [syncCompany()]   - Status: active
[SYNC_DEBUG] [syncCompany()] 🔍 Finding or creating local company record
[SYNC_DEBUG] [syncCompany()] ✅ Local company record ready: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncCompany()] 📝 Updating company properties...
[SYNC_COMPANY] 💺 Set 5 seated employees
[SYNC_DEBUG] [syncCompany()] 💾 Saving company to modelContext...
[SYNC_DEBUG] [syncCompany()] ✅ Company saved successfully
[SYNC_COMPANY] ✅ Company synced
[SYNC_DEBUG] [syncAll()] → Syncing Users...
[SYNC_DEBUG] [syncUsers()] 🔵 FUNCTION CALLED
[SYNC_USERS] 👥 Syncing users...
[SYNC_DEBUG] [syncUsers()] 📥 Fetching users from API for company: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB BEFORE sync: 4
[SYNC_DEBUG] [syncUsers()] 👑 Company has 1 admin IDs: ["1749432802202x703263025035244900"]
App is being debugged, do not track this hang
Hang detected: 1.45s (debugger attached, not reporting)
[PAGINATION] 📄 Page 1: Fetched 39 calendarevents (Total: 39)
[PAGINATION] ✅ Completed: Total 39 calendarevents fetched across 1 page(s)
Failed to locate resource named "default.csv"
App is being debugged, do not track this hang
Hang detected: 1.89s (debugger attached, not reporting)
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'SHEATHING' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Robin Wright' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Robin Wright' color from API: #a19673
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Daryl Watson' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'FRAMING WORK' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'John Smith' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Daryl Watson' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Evergreen Construction' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Evergreen Construction' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Deck Boards' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'Framing Work - Clean slate test Project' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Railings - Clean slate test Project' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Framing Work' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] ✅ Synced 39 calendar events
[SYNC_TASKS] ✅ Syncing tasks...
[SYNC_DEBUG] [syncUsers()] ✅ API returned 4 user DTOs
[PAGINATION] 📊 Starting paginated fetch for Task
[SYNC_DEBUG] [syncUsers()]   - User: Test User (ID: 1749432802202x703263025035244900, Role: Admin)
[SYNC_DEBUG] [syncUsers()]   - User: Pete Mitchell (ID: 1760051201910x723551976281209700, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Nick Bradshaw (ID: 1760052300279x108662282911617730, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()]   - User: Tom  Kazansky (ID: 1760052397233x324423650406588740, Role: Field Crew)
[SYNC_DEBUG] [syncUsers()] 🔍 Handling deletions - remote IDs count: 4
[SYNC_DEBUG] [syncUsers()] 📝 Upserting 4 users...
[SYNC_DEBUG] [syncUsers()]   [1/4] Processing user: Test User
[SYNC_DEBUG] [syncUsers()]     - 👑 Role set to ADMIN (in company.adminIds)
[SYNC_DEBUG] [syncUsers()]   [2/4] Processing user: Pete Mitchell
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [3/4] Processing user: Nick Bradshaw
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()]   [4/4] Processing user: Tom  Kazansky
[SYNC_DEBUG] [syncUsers()]     - Role set to: fieldCrew (from employeeType)
[SYNC_DEBUG] [syncUsers()] 💾 Saving 4 users to modelContext...
[SYNC_DEBUG] [syncUsers()] 📊 Users in DB AFTER sync: 4
[SYNC_DEBUG] [syncUsers()] ✅ Users synced successfully
[SYNC_USERS] ✅ Synced 4 users
[SYNC_DEBUG] [syncAll()] → Syncing Clients...
[SYNC_CLIENTS] 🏢 Syncing clients...
[SYNC_CLIENTS] ✅ Synced 13 clients
[SYNC_DEBUG] [syncAll()] → Syncing Task Types...
[SYNC_TASK_TYPES] 🏷️ Syncing task types...
[SUBSCRIPTION] Fetching company with ID: 1749432890812x563585058122141300
[SUBSCRIPTION] Full URL: https://opsapp.co/api/1.1/obj/company/1749432890812x563585058122141300
[PAGINATION] 📄 Page 1: Fetched 52 Tasks (Total: 52)
[PAGINATION] ✅ Completed: Total 52 Tasks fetched across 1 page(s)
[SYNC_TASKS] ✅ Synced 52 tasks
[SYNC_BG] ✅ Background refresh complete
[SUBSCRIPTION] Raw API Response for Company:
[SUBSCRIPTION] Date fields in response:
[SUBSCRIPTION]   Created Date: 2025-06-09T01:34:50.822Z
[SUBSCRIPTION]   Modified Date: 2025-11-20T17:55:43.462Z
[SUBSCRIPTION] seatedEmployees field: (
    1750977599033x353965879696517500,
    1760052300279x108662282911617730,
    1749432802202x703263025035244900,
    1760051201910x723551976281209700,
    1760052397233x324423650406588740
)
[SUBSCRIPTION] Response JSON (truncated): {
    "response": {
        "logo": "//21f8aef8a1eb969e43f8925ea58a2f93.cdn.bubble.io/f1760052614190x555463743569300400/channels4_profile.avif",
        "clients": [
            "1749433390580x459430916087611400",
            "1749433416591x491305525683159040",
            "1749433453320x656056024164728800",
            "1749433475674x137708773356601340",
            "1749433506218x593920412915335200",
            "1760553457890x454432096959072060",
            "1761181441307x489756751367648200",
            "1761759155434x159074945739295040",
            "1763509025227x692852893963504100",
            "1763661246094x959999678947481000"
        ],
        "qbConnected": false,
        "projects": [
            "1749433514282x402143493015994400",
            "1749433525330x509910274265841660",
            "1749433544398x644658077188227100",
            "1749433560900x375570893353779200",
            "1749433567369x519244473119539200",
            "1760551329635x214462564021837150",
            "1760553017732x459643017552842100",
            "1760553057960x848788932669397600",
            "1760553485041x328848046193623840",
            "1760053040074x897191029414202200",
            "1761156833428x451468226316574340",
            "1761161046758x931633369376104700",
            "1761162539485x177948205785155600",
            "1761172478275x262746266349336740",
            "1761173971446x462788748593081500",
            "1761174462261x646789331060738700",
            "1761181464028x514567553211649600",
            "1761267917908x754340491805805000",
            "1761268217255x190256784716349660",
            "1761278507610x624717899061788700",
            "1761759177820x920922776128854000",
            "1763363102567x223600379296342370",
            "1763364286137x710011798596255100",
            "1763403975497x994358677235182700",
            "1763509969216x863800873848467500",
            "1763526474110x984724149515322200",
            "1763578403953x524310636951218940",
            "1763578908485x147354716986443740",
            "1763609021721x425734433842798200",
            "1763661342904x581637806788413800"
        ],
        "registered": 100,
        "companyId": "1749432890812x563585058122141300",
        "employees": [
            "1749432802202x703263025035244900",
            "1760051201910x723551976281209700",
            "1760052300279x108662282911617730",
            "1760052397233x324423650406588740"
        ],
        "Created Date": "2025-06-09T01:34:50.822Z",
        "location": {
            "address": "1200 Fort St, Victoria, BC V8V, Canada",
            "lat": 48.4229532,
            "lng": -123.3498386
        },
        "companyAge": "5-10",
        "phone": "2588943323",
        "companySize": "3-5",
        "openHour": "08:00:00",
        "maxSeats": 10,
        "_id": "1749432890812x563585058122141300",
        "closeHour": "17:00:00",
        "subscriptionStatus": "active",
        "Slug": "test-company",
        "industry...
[CompanyDTO] Successfully decoded company with ID: 1749432890812x563585058122141300
[SYNC_TASK_TYPES] ✅ Synced 5 task types
[SYNC_DEBUG] [syncAll()] → Syncing Projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔵 FUNCTION CALLED (sinceDate: nil)
[SYNC_PROJECTS] 📋 Syncing projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 👤 Current user: 1749432802202x703263025035244900, Role: Admin
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB BEFORE sync: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📥 Fetching ALL company projects for company: 1749432890812x563585058122141300
[PAGINATION] 📊 Starting paginated fetch for Project
[PAGINATION] 📄 Page 1: Fetched 35 Projects (Total: 35)
[PAGINATION] ✅ Completed: Total 35 Projects fetched across 1 page(s)
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Admin/Office user - keeping all 35 projects
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ API returned 35 project DTOs
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Composite Decking Renovation (ID: 1749433560900x375570893353779200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Citygate Boulevard (ID: 1760052988218x653265573877647400, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings Installation (ID: 1749433525330x509910274265841660, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project Jacob (ID: 1760553485041x328848046193623840, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Rowhomes Project (ID: 1761267917908x754340491805805000, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Blanshard Renovation (ID: 1760551329635x214462564021837150, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1749433514282x402143493015994400, Status: Completed)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Project Deck Renovation (ID: 1761278507610x624717899061788700, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Glass Railings Installation (ID: 1749433544398x644658077188227100, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Pergola Framing (ID: 1749433567369x519244473119539200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project (ID: 1761156833428x451468226316574340, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project New (ID: 1761162539485x177948205785155600, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project OCTOBER 22 (ID: 1761161046758x931633369376104700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Next Test Project (ID: 1761174462261x646789331060738700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Photo Project (ID: 1761268217255x190256784716349660, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test project  TEST 4 (ID: 1761161518256x140411073446936370, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings & Vinyl (ID: 1761759177820x920922776128854000, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test project 11/16 (ID: 1763363102567x223600379296342370, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Railings (ID: 1760052837877x111242630189534200, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Reconstruction (ID: 1760053040074x897191029414202200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: James Bay Residences (ID: 1760053708654x396262514789569100, Status: Estimated)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Landsdowne Renovation (ID: 1760553017732x459643017552842100, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 5 (ID: 1760553057960x848788932669397600, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Project Based Test (ID: 1761172478275x262746266349336740, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project Pete (ID: 1761173859745x700938540474596500, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Trst reno (ID: 1761173971446x462788748593081500, Status: Archived)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Deck Renovation/Reconstruction (ID: 1761181464028x514567553211649600, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 2-11/16 (ID: 1763364286137x710011798596255100, Status: RFQ)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Clean slate test Project (ID: 1763403975497x994358677235182700, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 11/18 (ID: 1763509969216x863800873848467500, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 0827 (ID: 1763526474110x984724149515322200, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 1119.1 (ID: 1763578403953x524310636951218940, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 1119.2 (ID: 1763578908485x147354716986443740, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Test Project 11/19.2 (ID: 1763609021721x425734433842798200, Status: In Progress)
[SYNC_DEBUG] [syncProjects(sinceDate:)]   - Project: Tek Screw Replacement (ID: 1763661342904x581637806788413800, Status: Accepted)
[SYNC_DEBUG] [syncProjects(sinceDate:)] 🔍 Handling deletions - remote IDs count: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)]    Remote project IDs: 1761173859745x700938540474596500, 1763661342904x581637806788413800, 1761267917908x754340491805805000, 1760553017732x459643017552842100, 1749433567369x519244473119539200, 1761173971446x462788748593081500, 1760053040074x897191029414202200, 1763609021721x425734433842798200, 1763509969216x863800873848467500, 1749433560900x375570893353779200...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 🔵 FUNCTION CALLED
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 keepingIds count: 35
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)]    Remote project IDs to keep: 1761173859745x700938540474596500, 1763661342904x581637806788413800, 1761267917908x754340491805805000, 1760553017732x459643017552842100, 1749433567369x519244473119539200, 1761173971446x462788748593081500, 1760053040074x897191029414202200, 1763609021721x425734433842798200, 1763509969216x863800873848467500, 1749433560900x375570893353779200...
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] 📊 Local projects count: 35
[SYNC_DEBUG] [handleProjectDeletions(keepingIds:)] ✅ No projects were deleted
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER deletions: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📝 Upserting 35 projects...
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [1/35] Processing project: Composite Decking Renovation (ID: 1749433560900x375570893353779200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433416591x491305525683159040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [2/35] Processing project: Citygate Boulevard (ID: 1760052988218x653265573877647400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [3/35] Processing project: Railings Installation (ID: 1749433525330x509910274265841660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [4/35] Processing project: Test Project Jacob (ID: 1760553485041x328848046193623840)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760553457890x454432096959072060
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [5/35] Processing project: Rowhomes Project (ID: 1761267917908x754340491805805000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 16
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [6/35] Processing project: Blanshard Renovation (ID: 1760551329635x214462564021837150)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [7/35] Processing project: Deck Reconstruction (ID: 1749433514282x402143493015994400)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433416591x491305525683159040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [8/35] Processing project: Project Deck Renovation (ID: 1761278507610x624717899061788700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [9/35] Processing project: Glass Railings Installation (ID: 1749433544398x644658077188227100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [10/35] Processing project: Pergola Framing (ID: 1749433567369x519244473119539200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [11/35] Processing project: Test Project (ID: 1761156833428x451468226316574340)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [12/35] Processing project: Test Project New (ID: 1761162539485x177948205785155600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [13/35] Processing project: Test Project OCTOBER 22 (ID: 1761161046758x931633369376104700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [14/35] Processing project: Next Test Project (ID: 1761174462261x646789331060738700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [15/35] Processing project: Photo Project (ID: 1761268217255x190256784716349660)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [16/35] Processing project: Test project  TEST 4 (ID: 1761161518256x140411073446936370)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760553457890x454432096959072060
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [17/35] Processing project: Railings & Vinyl (ID: 1761759177820x920922776128854000)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [18/35] Processing project: Test project 11/16 (ID: 1763363102567x223600379296342370)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [19/35] Processing project: Railings (ID: 1760052837877x111242630189534200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [20/35] Processing project: Deck Reconstruction (ID: 1760053040074x897191029414202200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760053009663x246333797400918530
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [21/35] Processing project: James Bay Residences (ID: 1760053708654x396262514789569100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [22/35] Processing project: Landsdowne Renovation (ID: 1760553017732x459643017552842100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [23/35] Processing project: Test Project 5 (ID: 1760553057960x848788932669397600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433453320x656056024164728800
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [24/35] Processing project: Project Based Test (ID: 1761172478275x262746266349336740)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [25/35] Processing project: Test Project Pete (ID: 1761173859745x700938540474596500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433475674x137708773356601340
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [26/35] Processing project: Trst reno (ID: 1761173971446x462788748593081500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1749433390580x459430916087611400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [27/35] Processing project: Deck Renovation/Reconstruction (ID: 1761181464028x514567553211649600)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761181441307x489756751367648200
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [28/35] Processing project: Test Project 2-11/16 (ID: 1763364286137x710011798596255100)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [29/35] Processing project: Clean slate test Project (ID: 1763403975497x994358677235182700)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052815102x595639222853478400
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [30/35] Processing project: Test Project 11/18 (ID: 1763509969216x863800873848467500)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 3
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [31/35] Processing project: Test Project 0827 (ID: 1763526474110x984724149515322200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [32/35] Processing project: Test Project 1119.1 (ID: 1763578403953x524310636951218940)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [33/35] Processing project: Test Project 1119.2 (ID: 1763578908485x147354716986443740)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1760052934080x955352593255101700
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [34/35] Processing project: Test Project 11/19.2 (ID: 1763609021721x425734433842798200)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1761759155434x159074945739295040
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Team members: 1
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)]   [35/35] Processing project: Tek Screw Replacement (ID: 1763661342904x581637806788413800)
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Company ID: 1749432890812x563585058122141300
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Client ID: 1763661246094x959999678947481000
[SYNC_DEBUG] [syncProjects(sinceDate:)]     - Project images: 2
[SYNC_DEBUG] [syncProjects(sinceDate:)] 💾 Saving 35 projects to modelContext...
[SYNC_DEBUG] [syncProjects(sinceDate:)] 📊 Projects in DB AFTER sync: 35
[SYNC_DEBUG] [syncProjects(sinceDate:)] ✅ Projects synced successfully
[SYNC_PROJECTS] ✅ Synced 35 projects
[SYNC_DEBUG] [syncAll()] → Syncing Tasks...
[SYNC_TASKS] ✅ Syncing tasks...
[PAGINATION] 📊 Starting paginated fetch for Task
[PAGINATION] 📄 Page 1: Fetched 52 Tasks (Total: 52)
[PAGINATION] ✅ Completed: Total 52 Tasks fetched across 1 page(s)
[SYNC_TASKS] ✅ Synced 52 tasks
[SYNC_DEBUG] [syncAll()] → Syncing Calendar Events...
[SYNC_CALENDAR] 📅 Syncing calendar events...
[PAGINATION] 📊 Starting paginated fetch for calendarevent
[PAGINATION] 📄 Page 1: Fetched 39 calendarevents (Total: 39)
[PAGINATION] ✅ Completed: Total 39 calendarevents fetched across 1 page(s)
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'SHEATHING' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Robin Wright' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Robin Wright' color from API: #a19673
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Daryl Watson' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'FRAMING WORK' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Untitled Event' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'DECK BOARDS' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'RAILINGS' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Jacob Snettler' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'John Smith' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Daryl Watson' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #8c7a68
[SYNC_CALENDAR] 🎨 Setting task event 'Evergreen Construction' color from API: #8c6868
[SYNC_CALENDAR] 🎨 Setting task event 'Evergreen Construction' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Deck Boards' color from API: #909ab5
[SYNC_CALENDAR] 🎨 Setting task event 'Framing Work - Clean slate test Project' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Railings - Clean slate test Project' color from API: #688c8c
[SYNC_CALENDAR] 🎨 Setting task event 'Framing Work' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'Vertex Projects' color from API: #7a8c68
[SYNC_CALENDAR] 🎨 Setting task event 'All-Star Renovations' color from API: #909ab5
[SYNC_CALENDAR] ✅ Synced 39 calendar events
[SYNC_DEBUG] [syncAll()] → Linking Relationships...
[LINK_RELATIONSHIPS] 🔗 Linking all relationships...
[LINK_RELATIONSHIPS] ✅ Linked 337 relationships
[SYNC_DEBUG] [syncAll()] 📊 LOCAL DATA AFTER SYNC:
[SYNC_DEBUG] [syncAll()]   - Companies: 1
[SYNC_DEBUG] [syncAll()]   - Users: 4
[SYNC_DEBUG] [syncAll()]   - Clients: 13
[SYNC_DEBUG] [syncAll()]   - Task Types: 5
[SYNC_DEBUG] [syncAll()]   - Projects: 35
[SYNC_DEBUG] [syncAll()]   - Tasks: 52
[SYNC_DEBUG] [syncAll()]   - Calendar Events: 39
[SYNC_DEBUG] [syncAll()] ✅ Complete sync finished successfully at 2025-11-20 20:58:11 +0000
[SYNC_ALL] ✅ Complete sync finished
[SYNC_DEBUG] [syncAll()] 🔵 FUNCTION EXITING - syncInProgress set to false
[SYNC_ALL] ========================================
[SYNC_ALL] 🏁 FULL SYNC COMPLETED
[SYNC_ALL] ========================================
App is being debugged, do not track this hang
Hang detected: 3.47s (debugger attached, not reporting)
📅 MonthGridView: visibleMonth changed from 2025-11-20 20:58:17 +0000 to 2025-11-01 07:00:00 +0000
📅 Comparing months: old=2025-11-01 07:00:00 +0000 new=2025-11-01 07:00:00 +0000
📅 Same month, not scrolling
📅 MonthGridView: visibleMonth changed from 2025-11-01 07:00:00 +0000 to 2024-11-01 07:00:00 +0000
📅 Comparing months: old=2025-11-01 07:00:00 +0000 new=2024-11-01 07:00:00 +0000
📅 Scrolling to 2024-11-01 07:00:00 +0000
📅 MonthGridView: visibleMonth changed from 2024-11-01 07:00:00 +0000 to 2025-11-01 07:00:00 +0000
📅 Comparing months: old=2024-11-01 07:00:00 +0000 new=2025-11-01 07:00:00 +0000
📅 Scrolling to 2025-11-01 07:00:00 +0000
App is being debugged, do not track this hang
Hang detected: 1.21s (debugger attached, not reporting)
[UPDATE_CALENDAR_EVENT] 🔵 Updating calendar event 1763578909860x243046867652733980
[UPDATE_CALENDAR_EVENT] 📊 Current state - Connected: true, Authenticated: true
CoreData: debug: PostSaveMaintenance: incremental_vacuum with freelist_count - 26 and pages_to_free 5
[UPDATE_CALENDAR_EVENT] ✅ Updated locally and marked for sync
[SYNC] 📊 Found 1 items pending sync
[SYNC] ⏱️ Starting periodic sync retry timer (every 3 minutes)
[UPDATE_CALENDAR_EVENT] 🚀 [LAYER 1] Connected & Authenticated - attempting immediate sync to Bubble...
[UPDATE_CALENDAR_EVENT] 📅 Updating calendar event in Bubble...
[UPDATE_CALENDAR_EVENT] Event ID: 1763578909860x243046867652733980
[UPDATE_CALENDAR_EVENT] Updates: ["endDate": "2025-11-28T08:00:00Z", "duration": 1, "startDate": "2025-11-28T08:00:00Z", "active": true]
[UPDATE_CALENDAR_EVENT] 📤 Request Body JSON: {"endDate":"2025-11-28T08:00:00Z","duration":1,"startDate":"2025-11-28T08:00:00Z","active":true}
[UPDATE_CALENDAR_EVENT] 📡 PATCH to: api/1.1/obj/calendarevent/1763578909860x243046867652733980
[API_ERROR] HTTP 400 - Response body: {"statusCode":400,"body":{"status":"ERROR","message":"Unrecognized field: active"}}
[UPDATE_CALENDAR_EVENT] ❌ [LAYER 1] Immediate sync failed: httpError(statusCode: 400)
[UPDATE_CALENDAR_EVENT] 🔄 [LAYER 2] Will retry on network change
[UPDATE_CALENDAR_EVENT] ⏱️ [LAYER 3] Will retry via 3-minute timer
Error updating task schedule: httpError(statusCode: 400)
