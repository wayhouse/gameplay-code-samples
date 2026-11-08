# Gameplay code samples

**Wayhouse Zhou** · Game developer

## Mondo Guess · JavaScript

Mondo Guess was a two-player card game I designed and programmed for WeChat. Both players had five seconds to memorize eight rock-paper-scissors cards. Once the cards turned face down, players took turns picking three each. Watching which cards the other player took could help you decide how to order your hand.

The original clients received a shared seed from the WeChat room and exchanged card positions when a player made a move. This standalone portfolio adaptation was written with Codex assistance. It runs two clients in memory, each with its own match state, and delivers the same ordered JSON messages to both.

### Run the replay

From this repository's root, use Node.js 22 or later. Both commands use only Node's built-in modules.

```sh
node mondo-guess/demo.js
node --test mondo-guess/match.test.js
```

The demo prints the shared deal, six alternating picks, the first drafter's exchange and a change to each player's hand order. Every card keeps its original ID as it moves. After each message the demo checks that both clients agree, then prints the final hands. In the default run, player 2 drafts first and finishes with Rock **#0**, Scissors **#6** and Paper **#3**.

To try a different room, pass an eight-digit seed such as `node mondo-guess/demo.js 11111111`. In the original deal code, changing the sign of a card after one sign reached its limit could leave the counts out of step with the cards actually dealt. The adaptation counts the sign it assigns. Even with eight identical digits, neither client deals more than three of any sign.

[Match rules and move validation](mondo-guess/match.js) · [Two-client replay](mondo-guess/demo.js) · [Regression tests](mondo-guess/match.test.js)

## Patchwork Bots · Luau

Patchwork Bots is my Roblox game in development. A robot following its owner can leave formation to collect nearby scrap and then rejoin. The server-side [collection module](patchwork-bots/RobotFollowCollectionService.luau) coordinates that detour.

- In `Collection.Update`, the robot reserves a scrap target before moving toward it. On arrival, it asks the world service to collect the item.
- In `planRoute`, a path request can finish after the player has changed the robot's orders. The callback checks that its plan and target still belong to the active task before using the result.
- In `Collection.Cancel`, the robot releases the reservation so another robot can pick up the scrap.

This is an excerpt from the Roblox project. Running it requires the project's robot navigation, movement recovery and world scrap services. I define the expected behavior, use Codex for implementation and debugging, and direct the follow-up checks in Roblox Studio. One check sent two robots after the same piece of scrap and verified that their combined cargo increased by exactly one item.

[Watch gameplay](https://www.youtube.com/watch?v=EsPRhQwVsPE) · [Play on Roblox](https://www.roblox.com/games/122920675229256/Patchwork-Bots)
