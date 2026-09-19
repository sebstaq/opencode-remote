# Open questions — chat message-list behaviour

Status: draft for the product owner (Phase 1 → Phase 2 bridge). See `chat-behavior-foundation.md`.
These are decisions only the owner can make. The foundation supplies observed behaviour; it does not answer these. The deep pass may add or refine items.

## A. The bottom, and the follow state

1. What exactly defines "at the bottom" — a distance band, a visible element, or a marker?
2. How many points is the band?
3. Is the same band used for detaching and re-attaching, or two different values (hysteresis)?
4. If the content is shorter than the viewport, does "at the bottom" apply at all?
5. When content is short, is it pinned to the bottom or to the top of the area?
6. Should the band scale with accessibility text sizes and different screen sizes?
7. Is following a single on/off state, or several states (at-bottom, following, anchored, detached, correcting)?
8. What is the single source of truth for the scroll position while a reply streams?
9. If both our code and the system adjust the scroll position, who wins?
10. Do we ever force the view to the bottom without the reader asking?
11. Should the follow state survive keyboard show/hide, rotation and app backgrounding?
12. What happens to the follow state when the viewport resizes mid-stream?

## B. Sending a message

13. On send, do we chase the reply, or hold the reader's own message in place ("read mode")?
14. If we hold the reader's message, exactly where does it sit (top of the viewport, an offset, centered)?
15. If the reader's own message is taller than the viewport, what part do we show?
16. Does sending always return to the bottom, even if the reader was reading history far above?
17. Does the view move the moment the reader sends, or only when the server confirms?
18. If the send fails, where does the view sit and what is shown?
19. Does a failed message stay in the thread, and does it affect following?
20. Do we show the reader's message immediately, before the server confirms?
21. Does sending dismiss the keyboard, and does that resize move the view?
22. Does the composer keep focus after sending?
23. What if the reader sends two messages in quick succession?
24. If the reply starts instantly vs after a long pause, is the behavior the same?
25. If the reader sends while detached, do we jump to their new message?

## C. Streaming and growing content

26. Does the view follow every token, every paragraph, every completed message, or not at all?
27. What unit of change triggers a follow (text growth, a new block, a tool call, an attachment)?
28. Do we animate the follow, or jump instantly?
29. Is the follow animated while pinned but instant while catching up?
30. Do we batch scroll updates to once per frame?
31. Do tool-call blocks and reasoning blocks count as content that triggers following?
32. When a collapsible block expands or collapses, does the view move?
33. When an image or attachment finishes loading and changes height, does the view jump?
34. If content *above* the viewport changes height while we are at the bottom, do we stay at the bottom?
35. If content above changes height while we are detached, do we compensate?

## D. Detaching

36. What ends the follow — position, gesture, or both?
37. Which gestures count (drag, wheel, scrollbar, keyboard keys, tap)?
38. How small an upward movement should detach?
39. If the reader nudges up by one point and releases, do we detach?
40. If the reader is mid-fling, do we detach immediately or after it settles?
41. If the reader scrolls up and then back to the bottom, do we re-attach automatically?
42. How do we tell a deliberate scroll from a programmatic or system-made movement?
43. If the system itself adjusts the position, do we undo it, ignore it, or stay detached?
44. Does a tap (no scroll) detach? Does a long-press? Does selecting text?
45. Does tapping a link or a control inside a message detach?
46. Does opening the keyboard detach?
47. Does rotating the device detach or preserve the position?

## E. Being off-bottom while content grows

48. Must the visible content stay *exactly* fixed while detached, or within a small tolerance?
49. What is the anchor — the topmost visible element, a named element, or a pixel offset?
50. If the anchored element is edited, deleted or regenerated, where does the view go?
51. If rows above the anchor change height, do we compensate?
52. Do we show any indication that new content arrived while detached?
53. If the reader is detached and the agent finishes, do we do anything?
54. If the reader is detached and a permission prompt arrives, do we move to it?
55. If the reader is detached at the very top, does new content change anything?

## F. The jump-to-latest control

56. Do we have a control at all?
57. When does it appear and disappear (threshold, hysteresis, debounce)?
58. Where is it positioned?
59. Does it show a count of unseen messages, a dot, or nothing?
60. Does it show while the agent is writing, when idle, or both?
61. Does it appear on session switch when the restored position is not at the bottom?
62. Exactly what does it do — scroll to the bottom and resume following?
63. Is its scroll animated or instant?
64. Does it appear when the reader is only slightly off the bottom?
65. How is it labeled and announced for assistive technology?

## G. Switching sessions

66. On opening a session, do we always land at the bottom, or restore a previous position?
67. If we restore, is it per session?
68. How long is a stored position kept, and does it survive an app restart?
69. If a session was streaming when we left, do we follow or anchor when we return?
70. Does switching reset the jump-to-latest state?
71. Do we restore the exact position or an approximation?
72. What if the session changed while we were away (new messages arrived)?
73. How does switching interact with loading older history?
74. Is there a loading state, and where does the view sit meanwhile?
75. If switching fails (unreachable server), what does the view show?
76. Does switching between computers behave the same as switching sessions?

## H. Older history

77. Does older history load automatically or only when the reader scrolls up?
78. How far from the top triggers loading?
79. Do we load older history when the first page does not fill the viewport?
80. When older content is added above, must the visible content stay fixed, and within what tolerance?
81. What if the anchor row is part of the newly loaded older content?
82. Is there a loading indicator, and where?
83. Can the reader keep scrolling while older content loads?
84. What happens if loading fails — retry, indicator, silence?
85. Do we ever load *all* history automatically?
86. How do we behave at the boundary of a very long history?

## I. Reply-start anchoring ("read mode")

87. In read mode, when does it end?
88. When the reply fills the viewport, do we start following automatically?
89. If the reader scrolls down a little, do we resume following?
90. Does the sent message stay visible or scroll away as the reply grows?
91. What if the reply is shorter than the screen?
92. How do follow-ups and multiple turns behave?

## J. Errors, reconnection and lifecycle

93. What happens to the position when a run aborts or errors?
94. When the connection drops and reconnects, does the view jump?
95. When the app is backgrounded and foregrounded, do we keep position and follow state?
96. When the app is relaunched, do we restore position?
97. When content arrives after a reconnect, do we follow or stay put?
98. What if messages arrive out of order or duplicated?
99. What if a visible message is edited, deleted or regenerated?
100. If the reader is detached and an error banner appears, do we move to it?

## K. Motion and animation

101. Should auto-follow be animated or instant, and when?
102. Should new messages animate in, and may that move the view?
103. Should the jump-to-latest scroll be animated?
104. Does an in-progress animation count as programmatic movement for detaching?
105. What is the reduced-motion behavior?
106. Do we animate the appearance of the jump-to-latest control?
107. Should streaming text animate, and could that fight the scroll?

## L. Accessibility

108. How is appended content announced?
109. Polite/queued vs interrupting — and when is interrupting allowed?
110. How do we avoid announcing every streamed token?
111. Do we announce when a reply is complete?
112. Do we announce the jump-to-latest control's appearance?
113. How is the scroll position conveyed to assistive technology?
114. How do we behave with very large text that reflows constantly?
115. Should follow behavior change for reduced-motion or screen-reader users?
116. How are errors and permission prompts announced?

## M. Tools, permissions and non-text content

117. Does a permission prompt scroll into view if the reader is at the bottom? If detached?
118. Do tool-call results trigger following?
119. Does expanding/collapsing reasoning move the view?
120. Do late-loading images or attachments cause jumps?
121. Do file cards or previews count as new content for following?
122. What if non-text content is taller than the viewport?

## N. Layout and environment edge cases

123. How does the keyboard opening/closing change the available height and the follow state?
124. How do we handle safe areas and the home indicator?
125. How do we behave on larger screens and split views?
126. What about rotation during a stream?
127. What about a very long single message?
128. What about a burst of many messages at once, or an extremely slow stream?
129. Two devices on the same session — does each follow independently?
130. Empty session / the very first message in a session.
