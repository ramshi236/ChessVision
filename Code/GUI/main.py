import chess
# import chess.uci
import chess.svg
import time
import sys
from chessboard import display


in_path = "input.txt"
out_path = "output.txt"

with open(in_path, 'w') as _:
    pass

with open(in_path, 'r') as in_file:
    display.start('8/8/8/8/8/8/8/8')
    state = 0
    while True:
        new_line = in_file.readline()
        if not new_line:
            time.sleep(1)
            continue
        new_line = new_line[0:-1]

        if new_line == 'reset':
            state = 0
            display.start('8/8/8/8/8/8/8/8')
            continue

        if new_line == 'stop':
            display.terminate()
            print('Game stopped. Bye bye.')
            break

        if state == 0:  # first board is detected
            fen = new_line
            print(fen)
            board = chess.Board(fen=fen)

            illegal = int(not board.is_valid())
            with open(out_path, 'w') as out_file:
                out_file.write(str(illegal))

            if not illegal:
                state = 1
                display.start(fen)
                continue

        if state == 1:
            new_move = new_line
            illegal = int(not chess.Move.from_uci(new_move) in board.legal_moves)
            if not illegal:
                board.push(chess.Move.from_uci(new_move))
                display.start(board.fen())

            with open(out_path, 'w') as out_file:
                out_file.write(str(illegal))
