package build

import "core:fmt"
import "core:log"
import os "core:os/os2"
import "core:slice"
import "core:strings"
import "core:time"
import "core:time/datetime"

main :: proc() {
	context.logger = log.create_console_logger()

	now := time.now()
	today: datetime.Date = {i64(time.year(now)), i8(time.month(now)), i8(time.day(now))}

	EXE :: "dawnsea"
	OUT :: EXE + ".exe" when ODIN_OS == .Windows else EXE
	run_str(
		"odin build src -collection:src=src -debug -o:none -out:" + OUT + " -error-pos-style:unix",
	)

	log.infof("Build completed at {}", fmt.aprintf("%v-%v-%v", today.year, today.month, today.day))

	if slice.contains(os.args, "run") do run({OUT})
}

build_shaders :: proc() {
	log.info("Building shaders...")
	run_str(
		"./sokol-shdc -i src/simgui/shader.glsl -o src/simgui/shader.odin -l hlsl4 -f sokol_odin",
	)
	log.info("Shaders built.")
}

run_str :: proc(cmd: string) {
	run(strings.split(cmd, " "))
}

run :: proc(cmd: []string) {
	log.infof("Running {}", cmd)
	code, err := exec(cmd)
	if err != nil {
		log.errorf("Error executing process: {}", err)
		os.exit(1)
	}
	if code != 0 {
		log.errorf("Process exited with non-zero code {}", code)
		os.exit(1)
	}
}

exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
	process := os.process_start(
		{command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr},
	) or_return
	state := os.process_wait(process) or_return
	os.process_close(process) or_return
	return state.exit_code, nil
}
