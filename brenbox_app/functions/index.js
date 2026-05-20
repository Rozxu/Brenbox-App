const functions = require("firebase-functions");
const admin     = require("firebase-admin");

admin.initializeApp();

const db        = admin.firestore();
const messaging = admin.messaging();

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getUserToken(uid) {
  try {
    const doc = await db.collection("users").doc(uid).get();
    return doc.exists ? (doc.data().fcmToken || null) : null;
  } catch (_) { return null; }
}

async function writeHistory(userId, title, body, type, extra = {}) {
  const now = admin.firestore.Timestamp.now();
  const ref = await db.collection("notification_history").add({
    userId, title, body, type,
    isRead: false,
    createdAt: now,
    scheduledFor: now,
    ...extra,
  });
  return ref.id;
}

// Returns "GroupName (Subject)" when subject exists, else just "GroupName"
function groupLabel(gName, gSubject) {
  return gSubject ? `${gName} (${gSubject})` : gName;
}

async function sendFcm(token, title, body, data) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      notification: { title, body },
      data,
      android: {
        notification: {
          channelId: data.channelId || "group_channel",
          priority: "high",
        },
        priority: "high",
      },
    });
  } catch (e) {
    // Token invalid — clean it up
    if (e.code === "messaging/registration-token-not-registered") {
      try {
        const snap = await db.collection("users")
            .where("fcmToken", "==", token).limit(1).get();
        snap.forEach((doc) => doc.ref.update({ fcmToken: null }));
      } catch (_) {}
    }
  }
}

// ── Group Messages → Chat tab (0) ─────────────────────────────────────────────

exports.onGroupMessage = functions.firestore
    .document("study_groups/{groupId}/messages/{msgId}")
    .onCreate(async (snap, context) => {
      const data     = snap.data();
      const groupId  = context.params.groupId;

      const groupDoc = await db.collection("study_groups").doc(groupId).get();
      if (!groupDoc.exists) return;
      const g        = groupDoc.data();
      const members  = g.memberIds || [];
      const gName    = g.name    || "Group";
      const gSubject = g.subject || "";
      const sender   = data.senderId;

      // Guard: if senderId is missing, skip — we cannot safely filter the sender
      if (!sender) return;

      const uname    = data.senderUsername || "Someone";
      let title, body, notifType;
      const label = groupLabel(gName, gSubject);
      switch (data.type) {
        case "event":
          title = `New Event in ${label}`;
          body  = `${uname} added an event: ${data.eventTitle || ""}`;
          notifType = "group_event"; break;
        case "poll":
          title = `New Poll in ${label}`;
          body  = `${uname} created a poll: ${data.pollQuestion || ""}`;
          notifType = "group_poll"; break;
        case "image":
          title = `New Message in ${label}`;
          body  = `${uname}: image📸`;
          notifType = "group_chat"; break;
        case "file":
          title = `New Message in ${label}`;
          body  = `${uname}: ${data.fileName || "file"}`;
          notifType = "group_chat"; break;
        default: {
          const text = (data.text || "").trim() || "Sent a message";
          title = `New Message in ${label}`;
          body  = `${uname}: ${text}`;
          notifType = "group_chat";
        }
      }

      const recipients = members.filter((id) => id !== sender);
      for (const uid of recipients) {
        const historyDocId = await writeHistory(uid, title, body, notifType, {
          groupId, groupName: gName, subject: gSubject, tab: 0,
        });
        const token = await getUserToken(uid);
        if (!token) continue;
        await sendFcm(token, title, body, {
          type: notifType, groupId, tab: "0", historyDocId,
          channelId: "group_channel",
          senderId: sender,
        });
      }
    });

// ── Group Milestones → Tasks tab (1) ──────────────────────────────────────────

exports.onGroupMilestone = functions.firestore
    .document("study_groups/{groupId}/milestones/{id}")
    .onCreate(async (snap, context) => {
      const data    = snap.data();
      const groupId = context.params.groupId;

      const groupDoc = await db.collection("study_groups").doc(groupId).get();
      if (!groupDoc.exists) return;
      const g       = groupDoc.data();
      const members = g.memberIds || [];
      const gName   = g.name    || "Group";
      const gSub    = g.subject || "";
      const creator = data.createdBy;

      const title = `New Task in ${groupLabel(gName, gSub)}`;
      const body  = `${data.createdByUsername || "Someone"} added: ${data.title || "a task"}`;

      for (const uid of members.filter((id) => id !== creator)) {
        const historyDocId = await writeHistory(uid, title, body, "group_milestone", {
          groupId, groupName: gName, subject: gSub, tab: 1,
        });
        const token = await getUserToken(uid);
        if (!token) continue;
        await sendFcm(token, title, body, {
          type: "group_milestone", groupId, tab: "1", historyDocId,
          channelId: "group_channel",
        });
      }
    });

// ── Group Updates → Updates tab (2) ───────────────────────────────────────────

exports.onGroupUpdate = functions.firestore
    .document("study_groups/{groupId}/updates/{id}")
    .onCreate(async (snap, context) => {
      const data    = snap.data();
      const groupId = context.params.groupId;

      const groupDoc = await db.collection("study_groups").doc(groupId).get();
      if (!groupDoc.exists) return;
      const g       = groupDoc.data();
      const members = g.memberIds || [];
      const gName   = g.name    || "Group";
      const gSub    = g.subject || "";
      const poster  = data.postedBy;

      const title = `New Update in ${groupLabel(gName, gSub)}`;
      const body  = `${data.postedByUsername || "Someone"} posted: ${data.title || "an update"}`;

      for (const uid of members.filter((id) => id !== poster)) {
        const historyDocId = await writeHistory(uid, title, body, "group_update", {
          groupId, groupName: gName, subject: gSub, tab: 2,
        });
        const token = await getUserToken(uid);
        if (!token) continue;
        await sendFcm(token, title, body, {
          type: "group_update", groupId, tab: "2", historyDocId,
          channelId: "group_channel",
        });
      }
    });

// ── Group Notes → Notes tab (3) ───────────────────────────────────────────────

exports.onGroupNote = functions.firestore
    .document("study_groups/{groupId}/notes/{id}")
    .onCreate(async (snap, context) => {
      const data    = snap.data();
      const groupId = context.params.groupId;

      const groupDoc = await db.collection("study_groups").doc(groupId).get();
      if (!groupDoc.exists) return;
      const g       = groupDoc.data();
      const members = g.memberIds || [];
      const gName   = g.name    || "Group";
      const gSub    = g.subject || "";
      const author  = data.authorId;

      const title = `New Note in ${groupLabel(gName, gSub)}`;
      const body  = `${data.authorUsername || "Someone"} added: ${data.title || "a note"}`;

      for (const uid of members.filter((id) => id !== author)) {
        const historyDocId = await writeHistory(uid, title, body, "group_note", {
          groupId, groupName: gName, subject: gSub, tab: 3,
        });
        const token = await getUserToken(uid);
        if (!token) continue;
        await sendFcm(token, title, body, {
          type: "group_note", groupId, tab: "3", historyDocId,
          channelId: "group_channel",
        });
      }
    });

// ── Group Invitations ─────────────────────────────────────────────────────────

exports.onGroupInvite = functions.firestore
    .document("group_invitations/{inviteId}")
    .onCreate(async (snap, context) => {
      const data      = snap.data();
      const inviteeId = data.inviteeId;
      if (!inviteeId) return;

      const inviter   = data.inviterUsername || "Someone";
      const groupName = data.groupName       || "a study group";
      const title     = "New Group Invite";
      const body      = `${inviter} invited you to join "${groupName}"`;

      const historyDocId = await writeHistory(inviteeId, title, body, "group_invite", {
        eventId: context.params.inviteId,
      });
      const token = await getUserToken(inviteeId);
      if (!token) return;
      await sendFcm(token, title, body, {
        type: "group_invite", historyDocId, channelId: "invite_channel",
        senderId: data.inviterId || "",
      });
    });

// ── Timetable Shares ──────────────────────────────────────────────────────────

exports.onTimetableShare = functions.firestore
    .document("timetable_shares/{shareId}")
    .onCreate(async (snap, context) => {
      const data        = snap.data();
      const recipientId = data.recipientId;
      if (!recipientId) return;

      const sender  = data.senderUsername || "Someone";
      const subject = data.subject        || "a subject";
      const title   = "Timetable Shared With You";
      const body    = `${sender} shared their ${subject} timetable with you`;

      const historyDocId = await writeHistory(recipientId, title, body, "timetable_invite", {
        eventId: context.params.shareId,
      });
      const token = await getUserToken(recipientId);
      if (!token) return;
      await sendFcm(token, title, body, {
        type: "timetable_invite", historyDocId, channelId: "invite_channel",
        senderId: data.senderId || "",
      });
    });
