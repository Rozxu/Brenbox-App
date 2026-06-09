================================================================================
                        BRENBOX - USER MANUAL
              Personal Academic Management Mobile Application
================================================================================

VERSION     : Beta V3
PLATFORM    : Android
BACKEND     : Firebase (Authentication, Cloud Firestore, Firebase Storage)
FRAMEWORK   : Flutter (Dart)

================================================================================
TABLE OF CONTENTS
================================================================================

  1.  Requirements 
  2.  Installation
  3.  Creating an Account (Register)
  4.  Logging In
  5.  Homepage Overview
  6.  Module 1  — Class Schedule & Timetable
  7.  Module 2  — Task Tracker
  8.  Module 3  — Exam Countdown
  9.  Module 4  — Grade Tracker
  10. Module 5  — Study Planner
  11. Module 6  — Study Group
  12. Module 7  — Certificate Repository
  13. Notifications
  14. Settings & Profile
  15. Troubleshooting

================================================================================
1. REQUIREMENTS 
================================================================================

  Device Requirements:
  - Android smartphone (Android 8.0 or higher recommended)
  - Active internet connection (Wi-Fi or mobile data)
  - Minimum 100MB free storage

================================================================================
2. INSTALLATION
================================================================================

  Install APK directly:
  1. Transfer the 2_CI230077_BrenBox/Application.apk file to your Android device.
  2. On your device, go to Settings > Security > Enable "Install Unknown Apps".
  3. Open the APK file and tap Install.
  4. Once installed, open BrenBox from your app drawer.

================================================================================
3. CREATING AN ACCOUNT (REGISTER)
================================================================================

  Option A — Email & Password:
  1. Open BrenBox and tap "Sign Up" on the login screen.
  2. Enter your email address, username, password, and confirm password.
     - Password must be 6–25 characters.
     - Password must contain at least one uppercase letter, one number,
       and one special character (e.g. !@#$).
  3. Tap "SIGN UP".
  4. A verification email will be sent to your registered email address.
  5. Open the email and click the verification link (If it isn't in your inbox, please check your spam folder).
  6. Return to BrenBox and log in with your credentials.

  NOTE: You cannot log in until your email is verified.

  Option B — Google Sign-In:
  1. On the login screen, tap "Sign in with Google".
  2. Select your Google account from the list.
  3. A Data Usage Permission dialog will appear — tap "ALLOW" to proceed.
  4. Your account will be created and you will be redirected to the Homepage.

================================================================================
4. LOGGING IN
================================================================================

  Email & Password Login:
  1. Enter your registered email and password.
  2. Tap "LOG IN".
  3. If your email is not yet verified, you will see an error message.
     Verify your email first before logging in.

  Google Sign-In:
  1. Tap "Sign in with Google" and select your account.
  2. If you are an existing user, you will be redirected to the Homepage.

  Forgot Password:
  1. Tap "Forgot Password?" on the login screen.
  2. Enter your registered email address.
  3. A password reset email will be sent to you.
  4. Click the link in the email to reset your password.

================================================================================
5. HOMEPAGE OVERVIEW
================================================================================

  After logging in, you will see the Homepage which includes:

  - Greeting        : Displays your username.
  - Weekly Calendar : Shows the current week. Tap a day to view its schedule.
  - Timetable Cards : Shows tasks and classes for the selected day,
                      colour-coded by type (Tasks = blue, Class = red, Group Events = purple).
  - Exam Countdown  : Shows upcoming exams with days remaining.
                      Study Plan cards appear directly below each exam card (represented in green).
  - Bottom Navigation Bar:
      [ Home ] [ Calendar ] [ + Add ] [ Grade % ] [ Files ]

  Tap the [ + ] button to quickly add a Class, Task, or Exam.

================================================================================
6. MODULE 1 — CLASS SCHEDULE & TIMETABLE
================================================================================

  ADDING YOUR FIRST CLASS:
  1. Tap the [ + ] button on the bottom navigation bar.
  2. Select the "Classes" tab.
  3. Fill in:
       - Class Name    : Subject name
       - Room          : Room number
       - Building      : Building name
       - Lecturer Name : Name of the lecturer
       - Start/End Date Options:
           None               = Single occurrence (pick one date)
           Academic Year/Term = Auto-fills all dates for the semester
           Manual (Repeating) = Select specific days and date range
       - Start Time & End Time
  4. Tap "Save Class".

  NOTE: The system will automatically detect time clashes.
        If a clash is found, you will be notified and the class will not be saved.

  ADDING MORE CLASSES TO AN EXISTING SUBJECT:
  1. Go to the Calendar screen and tap on a subject in the subjects section
  2. Inside the Subject Detail screen, tap the [ + ] icon to add more classes.
  3. Fill in the class details and tap "Save Class".

  SHARING YOUR TIMETABLE:
  1. Open a subject and tap the Share icon.
  2. Enter the registered BrenBox email of the student you want to share with.
  3. Tap Send. The recipient will receive an in-app notification.
  4. The recipient can Accept or Decline the share request.

  VIEWING YOUR TIMETABLE:
  - Homepage shows today's timetable automatically.
  - Calendar screen shows a full monthly view with all class entries.

================================================================================
7. MODULE 2 — TASK TRACKER
================================================================================

  ADDING A TASK:
  1. Tap the [ + ] button on the bottom navigation bar.
  2. Select "Task" tab.
  3. Fill in:
       - Task Title   : Name of the task
       - Task Details : Description or notes
       - Subject      : Select the related subject
       - Task Type    : Assignment / Project / Presentation / Quiz / Other
       - Due Date     : Pick the due date
       - Due Time     : Pick the due time
  4. Tap "Save Task".

  MANAGING TASKS:
  - View all tasks on the Homepage timetable or the Calendar screen.
  - Tap a task card to view details.
  - Toggle task status between "Pending" and "Complete" from the detail view.
  - Tasks marked as Complete will be moved to the completed section.

  EDITING / DELETING A TASK:
  - Open the task detail, tap the edit icon to edit or the delete icon to remove.

================================================================================
8. MODULE 3 — EXAM COUNTDOWN
================================================================================

  ADDING AN EXAM:
  1. Tap the [ + ] button on the bottom navigation bar.
  2. Select "Exams" tab.
  3. Fill in:
       - Exam Name  : Name of the exam
       - Subject    : Select the related subject
       - Type       : Final Exam / Test / Quiz 
       - Mode       : In Person / Online
       - Venue      : Location (for In Person exams)
       - Exam Date  : Pick the exam date
       - Start Time : Pick the start time
       - End Time   : Pick the end time
  4. Tap "Save Exam".

  VIEWING THE COUNTDOWN:
  - The Homepage displays an exam countdown section showing:
      TODAY   = Exam is today
      DONE    = Exam has already passed
      X DAYS  = Number of days remaining until the exam

  EDITING / DELETING AN EXAM:
  - Tap the exam card and use the edit or delete options.

================================================================================
9. MODULE 4 — GRADE TRACKER
================================================================================

  STEP 1 — SET UP GRADE RANGES (required before using calculator):
  1. On the Grade Tracker screen, tap the [ 📐 ] icon.
  2. Step 1: Select the grade labels used by your institution
             (e.g. A+, A, A-, B+, B, etc.).
  3. Tap "Continue".
  4. Step 2: Enter the Min and Max score for each selected grade.
     Rules:
       - Lowest grade must start at 0.
       - Highest grade must end at 100.
       - Ranges must be continuous with no gaps.
  5. Tap "Save Grade".

  STEP 2 — CALCULATE YOUR GRADE:
  1. Select your subject from the dropdown.
  2. Select your target grade.
  3. Enter each assessment row:
       - Assessment Name : e.g. Quiz, Assignment, Final Exam
       - Marks           : Marks you obtained (leave empty if not yet taken)
       - Full Marks      : Maximum marks for the assessment
       - %               : Weightage percentage (all rows must total 100%)
  4. The system will automatically calculate:
       - Total (%): Your current total percentage.
       - Target Needed (%): How much more you need to reach your target grade.
       - Marks Needed hint: Per-row estimate for pending assessments.
  5. Tap "SAVE" to save your result.

  NOTE: If your target grade is no longer achievable, the system will display
        the nearest grade you can still reach.

  EDITING SAVED GRADE RESULTS:
  - Scroll down to the Saved Results section.
  - Tap the three-dot menu on a saved result card and select "Edit Result".
  - Update individual assessment marks and target grade as needed.
  - Tap "Save" to apply the changes. Totals and grade will be recalculated.

================================================================================
10. MODULE 5 — STUDY PLANNER
================================================================================

  NOTE: A study plan can only be created if an exam has been registered.
        Each study plan is directly linked to a specific exam.

  CREATING A STUDY PLAN:
  1. Navigate to the Exam Countdown section.
  2. Tap on an exam entry and select "Add Study Plan".
  3. Fill in:
       - Plan Name : Title for your study plan (e.g. "Final Exam Revision")
       - Checklist : Add study tasks one by one (e.g. "Review Chapter 1")
                     Tap [ + ] to add more items.
  4. Tap "Save Task".

  MANAGING YOUR STUDY PLAN:
  - Open a study plan to view the checklist and live countdown to the exam.
  - Tap a checklist item to mark it as done. A progress bar shows completion.
  - When all items are marked done, the plan status changes to "COMPLETE".

  EDITING / DELETING:
  - Use the edit icon (pencil) to update the plan name or checklist.
  - Use the delete icon (trash) to permanently remove the plan.

================================================================================
11. MODULE 6 — STUDY GROUP
================================================================================

  NOTE: A study group can only be created from within a subject page.

  CREATING A STUDY GROUP:
  1. Open a subject from the subject list.
  2. Scroll to the Study Groups section and tap "+ Create Group".
  3. Enter a group name and tap Save.

  INVITING MEMBERS:
  1. Go back to the Subject Detail screen (where you created the group).
  2. Under the "+ New Group" button, you will see your created group listed.
  3. Tap the Invite icon next to the group.
  4. Enter the registered BrenBox email address of the student you want to invite.
  5. Tap Send Invite.
  6. The invited student will receive an in-app push notification.
  7. They can Accept or Decline from their calendar screen.

  INSIDE THE STUDY GROUP (4 Tabs):

  [ CHAT TAB ]
  - Send text messages in real time.
  - Tap the attachment icon to send:
      📷 Image   — pick from gallery or camera
      📄 File    — pick a PDF from device
      📊 Poll    — create a question with multiple options
      📅 Event   — set a group event with date and time
  - All members receive an instant push notification for new messages.

  [ MILESTONES TAB ]
  - Add shared group tasks with title, description, and optional due date.
  - Any member can mark a milestone as complete.
  - Completion status updates for all members in real time.

  [ UPDATES TAB ]
  - Tap "Post Note" to post a note.
  - Enter a title, body text, and optionally attach PDF or DOC files.
  - Files are uploaded to Firebase Storage and accessible to all members.

  [ EVENTS TAB ]
  - Scheduled group events can be created via the Chat tab beside the message box.

  LEAVING / REMOVING MEMBERS:
  - Group creator can remove members from the Members sheet.
  - Removed members will be navigated out of the group immediately.
  - If you are the last member and leave, the group will be deleted.

================================================================================
12. MODULE 7 — CERTIFICATE REPOSITORY
================================================================================

  UPLOADING A CERTIFICATE:
  1. Tap the [ Files ] icon on the bottom navigation bar.
  2. Tap the [ + Add Certificate ] button.
  3. Fill in:
       - Title    : Name of the certificate
       - Year     : Year the certificate was obtained
       - Tags     : Add at least one tag (e.g. "academic", "workshop", "award")
       - File     : Tap "Pick PDF" to select a PDF from your device
  4. Tap "Upload". A progress bar will show the upload status.

  VIEWING A CERTIFICATE:
  - Tap any certificate card to open it in the built-in PDF viewer.

  DOWNLOADING A CERTIFICATE:
  - Open the certificate viewer and tap the download icon.
  - The file will be saved to your device's Downloads/Brenbox/PDFs/ folder.

  SEARCHING & FILTERING:
  - Use the search bar to search by certificate title.
  - Use the Year filter to show only certificates from a specific year.
  - Use the Tag filter to show certificates by category.

  EDITING A CERTIFICATE:
  - Tap the three-dot menu on a certificate card and select "Edit".
  - You can update the title, year, and tags (the file itself is not re-uploaded).

  DELETING A CERTIFICATE:
  - Tap the three-dot menu and select "Delete".
  - Confirm the deletion. The file will be permanently removed from
    Firebase Storage and Firestore.

================================================================================
13. NOTIFICATIONS
================================================================================

  BrenBox automatically schedules notifications for:

  CLASS REMINDERS:
  - Evening before class (configurable time, default 8:00 PM)
  - 1 hour before class
  - 10 minutes before class
  - At class start time

  TASK REMINDERS:
  - 3 days, 2 days, 1 day before due date/time
  - 1 hour before due time
  - 10 minutes before due time
  - At due time

  EXAM REMINDERS:
  - 3 days, 2 days, 1 day before exam
  - 1 hour before exam
  - 30 minutes before exam
  - 10 minutes before exam
  - At exam start time

  STUDY PLAN REMINDERS:
  - Daily reminder at configured time (default 8:00 PM) until exam day
  - Message tone adapts based on your checklist completion percentage

  GROUP NOTIFICATIONS:
  - Instant notification for new group messages, updates, and milestones
  - 1 day before group event, 1 hour before, 10 minutes before, at event time
  - Instant notification for group invitations and timetable share requests

  NOTIFICATION SETTINGS:
  1. Go to Profile > Notification Settings.
  2. Toggle each category on or off.
  3. Adjust reminder times as needed.
  4. Tap Save to apply changes.

================================================================================
14. SETTINGS & PROFILE
================================================================================

  VIEWING YOUR PROFILE:
  - Tap the profile icon (top right of Homepage).
  - View your username, email, and account details.

  EDITING YOUR PROFILE:
  - Tap "Edit Profile" to update your username or profile picture.

  DARK MODE / LIGHT MODE:
  - Toggle between dark and light theme from the Profile screen.

  CHANGING YOUR PASSWORD:
  - Tap "Change Password" in Profile settings.
  - Enter your current password and the new password.
  - Tap Save.

  LOGGING OUT:
  - Tap "Log Out" from the Profile screen.
  - You will be redirected to the Login screen.

================================================================================
15. TROUBLESHOOTING
================================================================================

  PROBLEM: Cannot log in after registering.
  SOLUTION: Check your email inbox and verify your email address first.
            Check your spam/junk folder if you cannot find the verification email.

  PROBLEM: Notifications are not appearing.
  SOLUTION:
    - Ensure notification permissions are granted in device Settings > Apps > BrenBox.
    - Ensure exact alarm permissions are granted (Android 12+).
    - Go to Profile > Notification Settings and ensure notifications are enabled.
    - Delete and re-add the event to force reschedule.

  PROBLEM: App is slow or data is not loading.
  SOLUTION: Check your internet connection. BrenBox requires an active
            internet connection for all features.

  PROBLEM: Grade Tracker inputs are locked / greyed out.
  SOLUTION: You must set up your grade ranges first. Tap the [ 📐 ] icon
            on the Grade Tracker screen to configure your grade settings.

  PROBLEM: Cannot create a study plan.
  SOLUTION: A study plan requires a registered exam. Add an exam first
            via the [ + ] button before creating a study plan.

  PROBLEM: Cannot create a study group.
  SOLUTION: Study groups are linked to subjects. Open a subject from the
            subject list and create the group from within the subject page.

  PROBLEM: Study group invitation not received.
  SOLUTION: Ensure the email entered matches the recipient's registered
            BrenBox email exactly (case-insensitive). Ask the recipient
            to check their notification history inside the app.

  PROBLEM: Class not saving due to time clash.
  SOLUTION: The system detected an overlap with an existing class on the
            same day and time. Adjust the start/end time or date to avoid
            the clash.

================================================================================
                        END OF BRENBOX USER MANUAL
================================================================================
