require 'bundler/inline'

puts "Installing gems..."
gemfile do
  source 'https://rubygems.org'
  gem 'pry'
  gem 'tty-progressbar'
end
puts "Finished installing gems"

require 'fileutils'
require 'json'

def print_board(board)
  print "#{'-'*10}\n"
  board.each do |row|
    row.each do |column|
      print "|#{column.to_s.rjust(2, ' ')}"
    end
    print '|'
    puts
  end
end

def board_hash(board)
  board.reduce(:+)
end

def available_positions(board)
  positions = []
  board.each.with_index do |row, i|
    row.each.with_index do |col, j|
      if board[i][j] == 0
        positions << {x: i, y: j}
      end
    end
  end

  positions
end

def update_board_state(gamestate, player_symbol, position)
  gamestate[:board][position[:x]][position[:y]] = player_symbol
  gamestate[:board_hash] = board_hash(gamestate[:board])
end

def check_winner(gamestate)
  return if gamestate[:end]

  # Tie
  unless available_positions(gamestate[:board]).size.positive?
    gamestate[:end] = gamestate[:tie] = true
    return
  end

  # Horizontal
  gamestate[:board].find do |row|
    if row.sum == gamestate[:player_one][:symbol] * 3
      gamestate[:end] = gamestate[:player_one][:winner] = true
    elsif row.sum == gamestate[:player_two][:symbol] * 3
      gamestate[:end] = gamestate[:player_two][:winner] = true
    end
  end

  # Vertical
  (0..2).each do |column|
    total = gamestate[:board_hash][0 + column] + gamestate[:board_hash][3 + column] + gamestate[:board_hash][6 + column]
    if total == gamestate[:player_one][:symbol] * 3
      gamestate[:end] = gamestate[:player_one][:winner] = true
    elsif total == gamestate[:player_two][:symbol] * 3
      gamestate[:end] = gamestate[:player_two][:winner] = true
    end
  end
  
  # Diagonal
  # Diag 1
  total = gamestate[:board_hash][0] + gamestate[:board_hash][4] + gamestate[:board_hash][8]
  if total == gamestate[:player_one][:symbol] * 3
    gamestate[:end] = gamestate[:player_one][:winner] = true
  elsif total == gamestate[:player_two][:symbol] * 3
    gamestate[:end] = gamestate[:player_two][:winner] = true
  end

  # Diag 2
  total = gamestate[:board_hash][2] + gamestate[:board_hash][4] + gamestate[:board_hash][6]
  if total == gamestate[:player_one][:symbol] * 3
    gamestate[:end] = gamestate[:player_one][:winner] = true
  elsif total == gamestate[:player_two][:symbol] * 3
    gamestate[:end] = gamestate[:player_two][:winner] = true
  end
end

def give_reward(gamestate, winning_player)
  result = gamestate[winning_player]
  if winning_player == :player_one
    feed_reward(gamestate[:player_one], 1)
    feed_reward(gamestate[:player_two], 0)
  elsif winning_player == :player_two
    feed_reward(gamestate[:player_one], 0)
    feed_reward(gamestate[:player_two], 1)
  else
    feed_reward(gamestate[:player_one], 0.1)
    feed_reward(gamestate[:player_two], 0.5)
  end
end

# at the end of game, backpropagate and update states value
def feed_reward(player, reward)
  player[:states].reverse.each do |state|
    player[:states_value][state.to_s] ||= 0
    player[:states_value][state.to_s] += (player[:lr] * (player[:decay_gamma] * reward - player[:states_value][state.to_s]))
  end
end

def choose_action(player, positions, current_board, symbol)
  action = nil
  value = nil

  if rand(0..1.0) <= player[:exp_rate]
    action = positions.sample
  else
    value_max = -999
    moves_and_values = []
    positions.each do |position|
      next_board = Marshal.load(Marshal.dump(current_board))
      next_board[position[:x]][position[:y]] = symbol
      next_board_hash = board_hash(next_board)

      value = player[:states_value][next_board_hash.to_s] || 0
      
      moves_and_values << {move: position, value: value}
      if value.to_f >= value_max.to_f
        value_max = value
        action = position
      end
    end
    puts moves_and_values
  end
  
  # puts "#{action} #{value}"
  action
end

def reset(gamestate)
  gamestate[:rounds_played] += 1
  gamestate[:end] = false
  gamestate[:tie] = false

  gamestate[:player_one][:winner] = false
  gamestate[:player_one][:states] = []

  gamestate[:player_two][:winner] = false
  gamestate[:player_two][:states] = []
  gamestate[:board] = [
    [0,0,0],
    [0,0,0],
    [0,0,0]
  ]
  gamestate[:board_hash] = board_hash(gamestate[:board])
end

gamestate = {
  board: [
    [0,0,0],
    [0,0,0],
    [0,0,0]
  ],
  end: false,
  tie: false,
  player_one: {
    wins: 0,
    symbol: 1,
    winner: false,
    states: [],  # record all positions taken
    lr: 0.2,
    exp_rate: ARGV.any? {|v| v == '--train'} ? 0.5 : 0,
    decay_gamma: 0.9,
    states_value: File.exists?('player_one_brain.json') ? JSON.parse(File.read('player_one_brain.json')) : {},  # state -> value
  },
  player_two: {
    wins: 0,
    symbol: -1,
    winner: false,
    states: [],  # record all positions taken
    lr: 0.2,
    exp_rate: ARGV.any? {|v| v == '--train'} ? 0.3 : 0,
    decay_gamma: 0.9,
    states_value: File.exists?('player_two_brain.json') ? JSON.parse(File.read('player_two_brain.json')) : {},  # state -> value
  },
  board_hash: nil,
  rounds_played: 0
}
gamestate[:board_hash] = board_hash(gamestate[:board])

trap("SIGINT") { 
  puts "SIGINT recieved, saving data before exiting..."
  FileUtils.cp('player_one_brain.json', 'player_one_brain.json.bak') if File.exists?('player_one_brain.json') #insurance in case you ctrl-c during the file write
  File.write('player_one_brain.json', gamestate[:player_one][:states_value].to_json)
  FileUtils.cp('player_two_brain.json', 'player_two_brain.json.bak') if File.exists?('player_two_brain.json') #insurance in case you ctrl-c during the file write
  File.write('player_two_brain.json', gamestate[:player_one][:states_value].to_json)
  exit
}

def play_human(gamestate, rounds)
  while gamestate[:rounds_played] < rounds
    positions = available_positions(gamestate[:board])
    action = choose_action(gamestate[:player_one], positions, gamestate[:board], 1)
    update_board_state(gamestate, 1, action)
    gamestate[:board_hash] = board_hash(gamestate[:board])
    gamestate[:player_one][:states] << gamestate[:board_hash]
    print_board(gamestate[:board])

    # if player 1 won, or game is tied
    check_winner(gamestate)
    if gamestate[:end]
      if gamestate[:player_one][:winner]
        puts "Player 1 won!"
      end
      reset(gamestate)
    else
      # Player 2 plays their move
      puts "Pick your X move"
      y = gets
      puts "Pick your Y move"
      x = gets

      update_board_state(gamestate, -1, {x: x.to_i, y: y.to_i})
      print_board(gamestate[:board])

      check_winner(gamestate)
      if gamestate[:end]
        if gamestate[:player_two][:winner]
          puts "Player 2 won!"
          # give_reward(gamestate, :player_two)
        end

        reset(gamestate)
      end
    end
  end
end

def train(gamestate, rounds)
  start_time = Time.now
  gamestate[:player_one][:states_value] = {} unless ARGV.any?{|v| v == '--dont-wipe'}
  gamestate[:player_two][:states_value] = {} unless ARGV.any?{|v| v == '--dont-wipe'}
  bar = TTY::ProgressBar.new("Rounds played [:bar]", total: rounds)
  while gamestate[:rounds_played] < rounds
    bar.advance(1)
    # tmp = gamestate[:player_one]
    # gamestate[:player_one] = gamestate[:player_two]
    # gamestate[:player_two] = tmp

    # Player 1 plays their move
    positions = available_positions(gamestate[:board])
    action = choose_action(gamestate[:player_one], positions, gamestate[:board], gamestate[:player_one][:symbol])
    update_board_state(gamestate, gamestate[:player_one][:symbol], action)
    gamestate[:board_hash] = board_hash(gamestate[:board])
    gamestate[:player_one][:states] << gamestate[:board_hash]

    # if player 1 won, or game is tied
    check_winner(gamestate)
    if gamestate[:end]
      if gamestate[:player_one][:winner]
        gamestate[:player_one][:wins] += 1
        give_reward(gamestate, :player_one)
      elsif gamestate[:tie]
        give_reward(gamestate, nil)
      end
      reset(gamestate)
    else
      # Player 2 plays their move
      positions = available_positions(gamestate[:board])
      action = choose_action(gamestate[:player_two], positions, gamestate[:board], gamestate[:player_two][:symbol])
      update_board_state(gamestate, gamestate[:player_two][:symbol], action)
      gamestate[:board_hash] = board_hash(gamestate[:board])
      gamestate[:player_two][:states] << gamestate[:board_hash]

      check_winner(gamestate)
      if gamestate[:end]
        if gamestate[:player_two][:winner]
          gamestate[:player_two][:wins] += 1
          give_reward(gamestate, :player_two)
        elsif gamestate[:tie]
          give_reward(gamestate, nil)
        end

        reset(gamestate)
      end
    end
  end
  puts "Training took #{Time.now - start_time}s"
  puts "- #{(Time.now - start_time) / rounds}s per round"
end

if ARGV.any? {|v| v == '--train'}
  rounds = begin 
  rounds_var = ARGV.find {|v| v.start_with? '--rounds='}
  if rounds_var
    rounds_var.split('=').last.to_i
  else
    100_000
  end
end
  train(gamestate, rounds)
  puts "Player one wins: #{gamestate[:player_one][:wins]}"
  puts "Player two wins: #{gamestate[:player_two][:wins]}"
  puts "Player two win percentage: #{((gamestate[:player_two][:wins] / rounds.to_f) * 100).round(2)}% of the time"
  puts "Saving state"
  FileUtils.cp('player_one_brain.json', 'player_one_brain.json.bak') if File.exists?('player_one_brain.json') #insurance in case you ctrl-c during the file write
  File.write('player_one_brain.json', gamestate[:player_one][:states_value].to_json)
  FileUtils.cp('player_two_brain.json', 'player_two_brain.json.bak') if File.exists?('player_two_brain.json') #insurance in case you ctrl-c during the file write
  File.write('player_two_brain.json', gamestate[:player_one][:states_value].to_json)
else
  rounds = begin 
    rounds_var = ARGV.find {|v| v.start_with? '--rounds='}
    if rounds_var
      rounds_var.split('=').last.to_i
    else
      5
    end
  end
  play_human(gamestate, rounds)
end
