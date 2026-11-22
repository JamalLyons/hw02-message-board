import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "mocha";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const PROJECT_ID = "demo-hw02-rules";

/** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync("../firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

function authed(uid) {
  return env.authenticatedContext(uid).firestore();
}

function signedOut() {
  return env.unauthenticatedContext().firestore();
}

async function seedMessage(id, overrides = {}) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "messages", id), {
      text: "hello from alice",
      authorUid: "alice",
      authorName: "Alice",
      createdAt: serverTimestamp(),
      ...overrides,
    });
  });
}

function messageCreate(authorUid, authorName, text) {
  return {
    text,
    authorUid,
    authorName,
    createdAt: serverTimestamp(),
  };
}

describe("firestore.rules", () => {
  it("denies a signed-out read of messages", async () => {
    await seedMessage("m1");
    const db = signedOut();
    await assertFails(getDocs(collection(db, "messages")));
    await assertFails(getDoc(doc(db, "messages", "m1")));
  });

  it("denies a signed-out create", async () => {
    const db = signedOut();
    await assertFails(
      setDoc(doc(db, "messages", "m1"), messageCreate("alice", "Alice", "hi")),
    );
  });

  it("denies a cross-uid update of another user's message", async () => {
    await seedMessage("m1");
    const bob = authed("bob");
    await assertFails(
      updateDoc(doc(bob, "messages", "m1"), {
        text: "hacked",
        editedAt: serverTimestamp(),
      }),
    );
  });

  it("denies a cross-uid delete", async () => {
    await seedMessage("m1");
    const bob = authed("bob");
    await assertFails(deleteDoc(doc(bob, "messages", "m1")));
  });

  it("denies a forged authorUid on create", async () => {
    const bob = authed("bob");
    await assertFails(
      setDoc(
        doc(bob, "messages", "forged"),
        messageCreate("alice", "Mallory", "forged"),
      ),
    );
  });

  it("denies the owner changing authorUid on update", async () => {
    await seedMessage("m1");
    const alice = authed("alice");
    await assertFails(
      updateDoc(doc(alice, "messages", "m1"), {
        text: "still mine",
        editedAt: serverTimestamp(),
        authorUid: "bob",
      }),
    );
  });

  it("allows correct-author full CRUD", async () => {
    const alice = authed("alice");
    const bob = authed("bob");
    const ref = doc(alice, "messages", "m1");

    await assertSucceeds(
      setDoc(ref, messageCreate("alice", "Alice", "hello board")),
    );
    await assertSucceeds(getDoc(doc(bob, "messages", "m1")));
    await assertSucceeds(
      updateDoc(ref, {
        text: "hello edited",
        editedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(deleteDoc(ref));
  });

  it("denies creating a message with empty text", async () => {
    const alice = authed("alice");
    await assertFails(
      setDoc(doc(alice, "messages", "empty"), messageCreate("alice", "Alice", "")),
    );
  });

  it("treats users/{uid} as a write-once owner record", async () => {
    const alice = authed("alice");
    const bob = authed("bob");
    const userRef = doc(alice, "users", "alice");

    await assertFails(
      setDoc(userRef, {
        uid: "alice",
        firstName: "Alice",
        lastName: "Lyons",
        role: "student",
        registrationDateTime: serverTimestamp(),
        extra: "nope",
      }),
    );

    await assertSucceeds(
      setDoc(userRef, {
        uid: "alice",
        firstName: "Alice",
        lastName: "Lyons",
        role: "student",
        registrationDateTime: serverTimestamp(),
      }),
    );

    await assertFails(getDoc(doc(bob, "users", "alice")));

    await assertFails(
      updateDoc(userRef, {
        firstName: "Alicia",
      }),
    );
  });

  it("allows a signed-in get of a non-existent message", async () => {
    const alice = authed("alice");
    await assertSucceeds(getDoc(doc(alice, "messages", "not-written-yet")));
  });
});
