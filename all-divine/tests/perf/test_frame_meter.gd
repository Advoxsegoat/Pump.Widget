extends TestCase
## FrameMeter (tests/support/frame_meter.gd), the stopwatch the frame budgets use: it must measure what the game's frame costs, not
## what the machine was doing, so that a test of a budget does not fail because another process has the processors.


func test_the_threads_cpu_time_counts_work_and_not_waiting() -> void:
	var before := FrameMeter.thread_cpu_usec()
	assert_true(before >= 0, "this platform tells a thread's processor time")
	if before < 0:
		return
	var wall := Time.get_ticks_usec()
	OS.delay_msec(60)  # waiting: the wall clock moves 60 ms, the thread's own time hardly at all
	var waited := FrameMeter.thread_cpu_usec() - before
	assert_true(Time.get_ticks_usec() - wall >= 60000, "the wall clock saw the wait")
	assert_true(waited < 20000, "waiting cost the thread %d us of its own time" % waited)
	var at := FrameMeter.thread_cpu_usec()
	var sum := 0.0
	for i in 400000:
		sum += sqrt(float(i))
	var worked := FrameMeter.thread_cpu_usec() - at
	assert_true(worked > 0 and sum > 0.0, "work cost the thread %d us of its own time" % worked)


func test_stats_are_the_mean_the_99th_percentile_and_the_longest_in_milliseconds() -> void:
	var times: Array[int] = []
	for i in 100:
		times.append(1000 + i * 10)  # 1.00 to 1.99 ms
	times.append(9000)
	var s := FrameMeter.stats(times)
	assert_eq(s["count"], 101)
	assert_near(float(s["mean"]), (100 * 1000 + 10 * 4950 + 9000) / 101.0 / 1000.0, 1e-6)
	assert_near(float(s["p99"]), 1.99, 1e-6, "the 99th of 101 sorted values is the 100th: the largest but the outlier")
	assert_near(float(s["max"]), 9.0, 1e-6)
	assert_eq(FrameMeter.stats([] as Array[int]), {"count": 0, "mean": 0.0, "p99": 0.0, "max": 0.0})


func test_the_best_window_is_the_quietest_stretch() -> void:
	var times: Array[int] = [5000, 5000, 1000, 1000, 5000, 1000]
	assert_near(FrameMeter.best_window_mean(times, 2), 1.0, 1e-9)
	assert_near(FrameMeter.best_window_mean(times, 3), 7.0 / 3.0, 1e-9)
	assert_near(FrameMeter.best_window_mean(times, 99), 3.0, 1e-9, "a window longer than the run is the whole run")


func test_a_meter_holds_the_threads_time_for_its_budget_and_the_quietest_stretch_for_its_mean() -> void:
	var meter := FrameMeter.new()
	# 200 steps: the wall clock saw a busy machine (6 ms) in all but a quiet 120 (1 ms); the thread's own time was 1 ms throughout,
	# with two slow steps of 12 ms (a spike in the game itself).
	for i in 200:
		meter.wall.append(1000 if i >= 50 and i < 170 else 6000)
		meter.cpu.append(12000 if i in [3, 190] else 1000)
	var held := meter.held()
	assert_eq(held["basis"], "thread time")
	assert_near(float(held["mean"]), 1.0, 1e-9, "the quietest 120 steps of the thread's time")
	assert_near(float(held["p99"]), 1.0, 1e-9, "two spikes in 200 steps are not over one in a hundred of them: the 99th is the 198th of 200")
	assert_near(float(held["max"]), 12.0, 1e-9)
	var no_thread := FrameMeter.new()
	no_thread.wall.append(3000)
	assert_eq(no_thread.held()["basis"], "wall time", "a platform that tells no thread time is held to the wall clock")
