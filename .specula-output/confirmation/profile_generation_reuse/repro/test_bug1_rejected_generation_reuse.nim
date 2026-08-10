import config/[coordinator, profile]

const generation = 5'u64
const digest = "rejected-candidate"

proc message(
    kind: ProfileActivationMsgKind, authority = ProfileAuthority.policy, success = true
): ProfileActivationMsg =
  ProfileActivationMsg(
    kind: kind,
    authority: authority,
    generation: generation,
    digest: digest,
    success: success,
  )

var model = ProfileActivationModel(activeGeneration: 4, activeDigest: "known-good")
model =
  model.reduceProfileActivation(message(ProfileActivationMsgKind.beginCandidate)).model
model = model.reduceProfileActivation(
  message(ProfileActivationMsgKind.authorityPrepared, success = false)
).model

for authority in ProfileAuthority:
  model = model.reduceProfileActivation(
    message(ProfileActivationMsgKind.rollbackCompleted, authority)
  ).model

# This is a normal public admission call. Before the fix it redispatches the
# exact identity whose old completions can still be in flight.
try:
  model = model.reduceProfileActivation(
    message(ProfileActivationMsgKind.beginCandidate)
  ).model
except DesktopProfileError:
  echo "SAFE: rejected generation cannot be reused"
  quit(0)

# Model delayed successes from the first prepare/activate batches.
for authority in ProfileAuthority:
  model = model.reduceProfileActivation(
    message(ProfileActivationMsgKind.authorityPrepared, authority)
  ).model
model = model.reduceProfileActivation(
  message(ProfileActivationMsgKind.activationRequested)
).model
for authority in ProfileAuthority:
  model = model.reduceProfileActivation(
    message(ProfileActivationMsgKind.authorityActivated, authority)
  ).model

if model.activeGeneration == generation and model.activeDigest == digest:
  echo "BUG: delayed completions promoted rejected generation 5"
else:
  echo "SAFE: rejected generation was not promoted"
