### Fixed

- **Journey replans no longer stack on the search frame that settled them.** A finished search's callback, which replans with two planner calls that cannot yield, now waits for the next frame once its pump has searched, so a plan and the 2 ms search slice that produced it never share one frame.
