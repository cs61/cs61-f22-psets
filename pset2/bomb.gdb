set arch i386:x86-64
file bomb

init-if-undefined $run_bomb_continue = 0

define run-bomb
  if $_thread != 0
    kill
  end
  shell killall qemu-x86_64 >/dev/null 2>&1
  shell qemu-x86_64 -g 12948 bomb sol.txt & sleep 0.2
  target remote localhost:12948
  if $run_bomb_continue != 0
    continue
  end
end

document run-bomb
  Restart the bomb with sol.txt as input.
end

define rb
  run-bomb
end
