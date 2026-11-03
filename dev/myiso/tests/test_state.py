import tempfile
from pathlib import Path
from installer.services.state import InstallerState

def test_state_initial():
    with tempfile.TemporaryDirectory() as tmpdir:
        state_file = Path(tmpdir) / "state.json"
        state = InstallerState(state_file)
        assert state.get("preflight") == "pending"
        state.mark_done("preflight")
        assert state.get("preflight") == "done"
        state.save()
        # Reload
        state2 = InstallerState(state_file)
        assert state2.get("preflight") == "done"



