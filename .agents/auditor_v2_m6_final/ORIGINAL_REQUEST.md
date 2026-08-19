# ORIGINAL REQUEST — auditor_v2_m6_final

Perform Forensic Integrity Audit for Project RIVALS-PARADIGM v2:
1. Conduct deep code analysis across all files in `src/` to verify genuine implementations (no facade code, no dummy implementations, no hardcoded cheating, no unhandled shortcuts).
2. Execute `selene src/` and `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl`.
3. Verify compliance with user requirements R1 through R5 and all acceptance criteria.
4. Output binary verdict (CLEAN vs INTEGRITY VIOLATION) and detailed evidence in `handoff.md` and send message to parent.
