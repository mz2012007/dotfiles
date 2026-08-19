from pathlib import Path
from installer.services.state import InstallerState, STAGES

def test_state_initial():
    state = InstallerState(Path("logs/test-state.json"))
    assert state.get("preflight") == "pending"
    state.mark_done("preflight")
    assert state.get("preflight") == "done"
    state.save()
    # Reload
    state2 = InstallerState(Path("logs/test-state.json"))
    assert state2.get("preflight") == "done"
