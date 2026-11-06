
Structure
- Cost
- Power
- Bonus (flat and mult)
- Rules

New rules
* The base maximum hand size is 4. After committing, you discard down to 4 using the multi-select UI
* Players get a default +1 energy per turn, not +N
* Discards and destroys go to the same pile
* Decks will go to 30 cards and allow 4x copies of a given card
* Nothing happens when you draw on an empty deck
* Muted --  A muted card still scores but doesn't fire triggers.
* Squelched -- A squelched card doesn't score and its ongoing effects stop.
* Condemned -- A condemned card is discarded at the end of the turn
* Anchored -- anchored cards cannot be moved
* Fleeting -- like Condemned but it's back to your hand instead of to discard
* Fade -- like Condemned, but it unreveals
Note:
* Destroying as it stands is too powerful because it hits a card's immediate payoff as well as its long-term payoff. Condemned allows you to remove cards from the board without disrupting the current turn
* Muted and Squelched hit different sorts of powers: transient and persistent

Card ideas
* On reveal: Add three cards to your opponents' hand. The cards are: Cost 1, Power 0, Ability: Bonus x.75 while this is in hand
* When the leftmost card is moved left, Condemn it. When the rightmost card is moved right, Condemn it. (Normally this causes wraparound)
* On reveal: Look at the top 3 cards of your deck, draw one, shuffle the other two.
* On score: Permanently increase the mult of the card to the right by 1.2
* Ongoing: +1 Power for each card in all discard piles.
* Ongoing: This card costs 7 on turn 7 (Power 12, Cost 12)
* On reveal: randomly reorder both boards
* On reveal: create a copy of this card in your hand
* On reveal: each player chooses 5 cards in play and condemns the rest
* On commit: select one card on the board and squelch it permanently
* Ongoing: your hand size is +2
* On start: +1 energy this turn (on turn start, this only works if the card is revealed)
* On commit: if you committed no cards this turn, +2 power +2 mult
* On reveal: trigger your other on-reveals twice this turn
* On commit: each card (yours and opponents') scores twice this turn
* On reveal: this card moves to your enemy's board before the next score (Cost 3, Power -3, Mult: 1.2; this card subtracts score and the multiplier APPLIES the negative)
* On score: draw a card
* On reveal: select a card + On start: mute the selected card
* On score: mute N random enemy cards where N is this card's Power
* Ongoing: squelches no longer end at the end of the turn
* On reveal: discard a card in your hand, get +N mult where N is the discarded card's Cost
* Ongoing: each card's Power is equal to the lowest power card on that player's field
* On reveal: The next un-revealed card moves to a random location AFTER revealing, BEFORE scoring
* On discard: Get match-long x1.25 Bonus each time a user discards a card
* Ongoing: Condemned cards un-reveal instead of going to the pile at the end of a turn
* On squelch: Whenever this card is squelched, condemn it instead
* On score: Your cards cannot be muted this turn
* Ongoing: Cards without abilities or cards who are squelched get +4 Power
* Ongoing: Whenever a Condemned card is sent to the pile, +1 energy next turn (This might be some kind of trigger? On discard, if the card was condemned...)
* On commit: This card gets -1 Cost each time you commit while it's in your hand
* On reveal: Put N cards from your or your opponent's pile back into the deck
* On start: Each player chooses 2 cards and the rest are muted
* On reveal: target card gets Fleeting
* On reveal: Put a card you own from the pile onto the field and condemn this one
* On reveal: Put your entire deck into the pile
* On reveal: Shuffle both players' piles into their decks, then condemn this one
* On score: draw a card, -1 Power. When this card reaches 0 Power, it gets Fleeting
* 

Existing cards I want to salvage:

| Card      | Cost / flat | What it does                                                                                   |
| --------- | ----------- | ---------------------------------------------------------------------------------------------- |
| Ember     | 1 / 4       | On reveal, discard a card from your hand.                                                      |
| Fuse      | 2 / 1       | Each time an enemy card scores, +1 flat. At 5 flat it destroys itself and a random enemy card. |
| Fuse      | 2 / 1       | Each time an enemy card scores, +1 flat. At 5 flat it destroys itself and a random enemy card. |
| Cinder    | 3 / 7       | On reveal, discard a card from your hand.                                                      |
| Glutton   | 4 / 2       | On reveal, destroy another card of yours and gain its flat.                                    |
| Immolator | 5 / 4       | On reveal, destroy any number of your cards, then as many random enemy cards.                  |
| Eddy      | 2 / 1       | When moved, +2 to its +bonus until the walk ends.                                              |
| Mirror    | 2 / 0       | On reveal, copy an enemy card's current flat and bonus as its own.                             |
| Shepherd  | 3 / 3       | On reveal, swap places with another card on your row.                                          |
| Herald    | 4 / 3       | Ongoing: ×1.5 while on the far left of your row.                                               |
| Tempest   | 6 / 5       | On reveal, reverse the order of the enemy row                                                  |
| Sapling   | 2 / 1       | Each time it scores, ×+0.25 for the match.                                                     |
| Rain      | 2 / 1       | On reveal, each card in your hand gets +1 flat for the match.                                  |
| Whisper   | 1 / 1       | On reveal, +1 flat for the match (every reveal, so it grows with each replay).                 |
| Refrain   | 2 / 1       | Each time another of your cards reveals, +1 flat this round.                                   |
| Tinker    | 3 / 3       | On reveal, the card to its right costs 1 less for the match.                                   |
| Lantern   | 4 / 4       | On reveal, your first card next turn is free.                                                  |
| Reverb    | 6 / 5       | On reveal, it costs 2 less for the match.                                                      |
|           |             |                                                                                                |

Crew

The purpose of Crew is like 'commanders' in MtG, 'jokers' in Balatro, or 'classes' in Hearthstone. They are persistent changes to the game or deck rules which serve to enable a player's chosen strategy. We want to build around a few loose strategies to start:
* Greed/aggro: early score leads, raw number efficiency
* Combo: maximizing reveal and other triggers, requiring setup for big payoffs
* Disruption: squelching and muting to stop your enemy's win conditions
* Graveyard: Condemnation and discard, with tools to mitigate losses or recur cards
* Control: card movement and board manipulation to maximizing your scoring pipelines and undermine your opponent's
* Ramp: Maximizing persistent card improvements over an entire match to create dominant positions in later rounds

I want 9 different crew members with either evergreen abilities or ones to serve these strategies:
* Tallyman: every 4 score triggers, the next score gets +5 mult
* Shade: at the end of every turn, Shade un-reveals one of your cards (Choose from 3 randomly selected revealed cards)
* Veil: at the end of the turn, select one condemned card to go to your hand instead of the pile
* Navigator: the second time a card scores in a walk, it gets +2 permanent power
* Void: when you would draw on an empty deck, get 10 +2x1.5 before the next walk
* Engineer: +1 energy each turn, starting turn 3
* Quartermaster: Your maximum hand size is now 7
* Salvager: On commit, you may discard a card and draw a card
* Captain: The first card on your board gets permanent +1 Power on score