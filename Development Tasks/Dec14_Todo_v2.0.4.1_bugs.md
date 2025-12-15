# OPS v2.0.4.1 Bugs

## Dec 14, 2024

### Notes from clarification
- "OPS API Error 7" - needs investigation to determine what error code 7 maps to
- Reusable popup message element exists, need to find it (name unknown)
- Organization/billing bugs require investigation - may be Bubble or Stripe backend issues
- 5-second retry then background sync applies to ALL network operations
- Job board dashboard gesture issue is in the dashboard with status columns (different from UniversalJobBoardCard fix)

---

### Crashes
- project details view, tap add task button from task list area: app crashes after filling out task form sheet and saving. Task saves successfully, but app crashes
- Delete project from project details view: app crashes.

### Status Logic
- changing a project status to completed must change all task status that are not 'cancelled' to completed. If there are some that are not completed or cancelled, the user should be prompted to check that each task is complete. I thought this was implemented already, it may not be hooked up in every place where status is changed though.

### Scrolling/Gestures
- closed projects and archived projects sheets are not scrolling
- Job board dashboard: cannot swipe horizontally to next status list except outside project cards, gesture doesn't register on cards. Scrolling vertically does not work either

### Photo Gallery
- tapping on the Nth photo in gallery (project details view) needs to open that photo. Currently defaults to opening the first photo. Also need to be able to zoom to the pinch location. Can only zoom on center of image now.
- Photo gallery project details view, add photos button needs to be changed: make outline of a photo with a plus icon, place first slot in carousel.

### Search
- Closed and archived (projects) and cancelled and completed (tasks) sheets need a search bar

### Network/Sync
- When attempting to save anything, need to try for 5 seconds, then move to sync in background.
- When trying to save client name: OPS API Error 7 (note, had bad reception)
- Need to update the weak/no connection message. Looks ugly (currently all caps)
- When changing job status in job board dashboard, if weak/no connection, the status changes are not queued, they are just not saved at all

### Delete Actions
- Delete project from quick actions: don't show push notification. Just show the reusable popup message, with project deleted message.

### Organization Settings / Billing
- organization settings: need to figure out the billing screen's billing info section. Where is data coming from?
- Organizations settings, manage subscription, cancel subscription does not work (check that data for test company not corrupt)
- Organization settings, change plan: attempt to change plan, shows error: payment setup failed: missing payment details
  - also, when on change plan screen, if the current plan is selected, and current plan is active, the button text is showing 'reactivate'. Shouldn't the button be disabled if the selected plan is active?
  - 'help me choose' section has innaccurate descriptions for each plan (wrong seat numbers)
