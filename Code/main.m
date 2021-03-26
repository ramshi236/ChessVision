% ***************************************
% Chess Vision - Digital Image Processing
%                                           
% Ariel Moshe, Roy Schneider, Ram Shirazi
% ***************************************

clc
clear
close all
addpath(genpath('.'))

isPlot = true; % bolean for plots
url = "http://192.168.1.15:8020/videoView";
cam = ipcam(url);

%% Step 1: Calibration
waitfor(helpdlg({'Welcome to ChessVision'; 'Please setup the board and place white pawn on 1A square.'},'Welcome'))
while true
    preview(cam)
    waitfor(helpdlg('Press OK when board setup is ready', 'Calibration'));
    closePreview(cam)
    while true
        I = cam.snapshot;
        [tform, BB] = calibrateBoard(I, false);
        if ~isempty(tform)
            break
        end
    end
    
    button = questdlg('Continue or calibrate again?', 'Calibration', 'Continue', 'Calibrate', 'Continue');
    if strcmp(button, 'Calibrate')
        close
    else
        if ~isPlot
            close
        end
        break
    end
end

%% Step 2: Run game
close all
reset = true;
while reset
    
    % Pieces classification
    while true
        waitfor(helpdlg('Press Ok when the board is clean', 'Piece Classification'));
%         [pieceNames] = classifyPieces(cam, tform, BB,isPlot);
        pieceNames = defaultBoard();
        fen = board2fen(reshape(pieceNames,8,8));
%         ilegalBoard = displayBoard(fen);
        ilegalBoard = 0;
        if ilegalBoard
            waitfor(helpdlg('Ilegal board!!! Please try again'));
        else
            break
        end
    end


    button = questdlg('Whos turn?', 'Choose sides', 'White', 'Black', 'White');
    if strcmp(button, 'White')
        whiteTurn = true;
    elseif strcmp(button, 'Black')
        whiteTurn = false;
    end
 
    % Moves tracking
    reset = trackMoves(cam, tform, pieceNames, whiteTurn, isPlot);
end

%% Functions

% main functions
function [tform, BB] = calibrateBoard(image, manual)
tform = [];
BB = [];
rot90 = false;
rot180 = false;
gridPoints = generateCheckerboardPoints(Consts.BOARDSIZE, Consts.SQUARESIZE) + Consts.SQUARESIZE;

% find transformation
[detectedPoints,boardSize] = detectCheckerboardPoints(image,'MinCornerMetric',0.1);
if  ~isequal(boardSize,Consts.BOARDSIZE)
    disp('Failed to detect board')
    return
else
    tform = fitgeotrans(detectedPoints,gridPoints,'projective');
end

% change major axes of squares counting in case low-left corner isn't black
transImage = imwarp(image,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
BW = binBoard(transImage);
boardMeans = calcSqaureMeans(BW);

if manual
    figure
    imshow(transImage)
    button = questdlg('Rotate by 90 deg counter clock wise?', 'Manual calibration', 'Yes','No','Yes');
    if strcmp(button, 'Yes')
        rot90 = true;
    end
    close
end

if (boardMeans(8,1) > boardMeans(1,1) && ~manual) || (manual && rot90)
    detectedPoints = reshape(detectedPoints, [7 7 2]);
    detectedPoints = permute(fliplr(detectedPoints), [2 1 3]);
    detectedPoints = reshape(detectedPoints, [49 2]);
    tform = fitgeotrans(detectedPoints,gridPoints,'projective');
    transImage = imwarp(image,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
    BW = binBoard(transImage);
    boardMeans = calcSqaureMeans(BW);
end

% rotate transform by 180 deg in case calibration pawn located in up-right corner
if manual
    figure
    imshow(transImage)
    button = questdlg('Rotate by 180 deg?', 'Manual calibration', 'Yes','No','No');
    if strcmp(button, 'Yes')
        rot180 = true;
    end
    close
end

if (boardMeans(1,8) > boardMeans(8,1) && ~manual) || (manual && rot180)
    detectedPoints = flip(detectedPoints);
    tform = fitgeotrans(detectedPoints,gridPoints,'projective');
end

transImage = imwarp(image,tform);
[centers, radii] = imfindcircles(transImage,[10 100]);
[r,maxIdx] = max(radii);
[x,y] = deal(centers(maxIdx,1) - r, centers(maxIdx,2) - 4*r);
dx = 2*r;
dy = 5*r;
BB = [x,y,dx,dy];

if ~manual
    transImage = imwarp(image,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
    gridPoints = generateCheckerboardPoints(Consts.BOARDSIZE, Consts.SQUARESIZE) + Consts.SQUARESIZE;
    figure(1)
    sgtitle('Board Calibration')
    subplot(1,2,1)
    imshow(image)
    hold on
    plot(detectedPoints(:,1),detectedPoints(:,2),'ro')
    subplot(1,2,2)
    imshow(transImage)
    hold on
    plot(gridPoints(:,1),gridPoints(:,2),'ro')
end
end

function [pieceNames] = classifyPieces(cam, tform, BB, isPlot)
imds = imageDatastore('images');
labels = cell(1,12);
for i = 1:length(imds.Files)
    labels{i} = imds.Files{i}(end-5:end-4);
end

pieceNames = strings(1,64);
% load('fen.mat')

I = cam.snapshot;
transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
BW = threshBoard(transImage);
numPixels = numel(find(BW));
refImage = im2single(rgb2gray(I));
thresh = 0.03;

figure(2)
sgtitle("Piece Classification")
subplot(1,3,2)
imshow(transImage);
pause(0.25)

squareSize = Consts.SQUARESIZE;
[x,y] = meshgrid((1:squareSize:8*squareSize) + round(squareSize/2), ...
    (1:squareSize:8*squareSize) + round(squareSize/2));
text(x(:),y(:),pieceNames,'HorizontalAlignment','center','FontSize', 20, 'Color','r' )
title('Detected Pieces')

state = 0;
disp('Place new piece to detect')
while true
    I = cam.snapshot;
    transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
    BW = threshBoard(transImage);
    newNumPixels = numel(find(BW));
    metric = abs(newNumPixels - numPixels);
    figure(2)
    subplot(1,3,3)
    imshow(BW)
    title('Hand Tracking')
    
    % to exit hold your hand for 5 seconds
    if metric < 3000
        tic
    end
    
    time = toc;
    
    if time > 10
        button = questdlg('Start playing?', 'Classification paused', 'Yes', 'Not yet', 'Yes');
        if strcmp(button, 'Yes')
            break
        else
            tic
        end
    end
    
    switch state
        case 0 % track for new piece
            corrs = zeros(1,12);
            I = cam.snapshot;
            transImage = imwarp(I,tform);
            croppedImage = rgb2gray(imcrop(transImage,BB));
            croppedImage = imresize(croppedImage,[220,90]);
            
            if isPlot
                figure(2)
                subplot(1,3,1)
                imshow(croppedImage)
            end
            for i = 1:length(imds.Files)
                groundTruth = imread(imds.Files{i});
                corrs(i) = corr2(groundTruth,imhistmatch(croppedImage,groundTruth));
            end
            
            [maxCorr, pos] = max(corrs);
            if maxCorr > 0.82
                state = 1;
                figure(2)
                subplot(1,3,1)
                pause(0.1)
                title(labels{pos})
                label = labels{pos};
                figure(3)
                groundTruth = imread(imds.Files{pos});
                matchedImage = imhistmatch(croppedImage,groundTruth);
                imshow(imtile({croppedImage, groundTruth, matchedImage}))
                disp('Piece detected')
                pause(1)
                disp('Move piece to its location')
            else
                figure(2)
                subplot(1,3,1)
                title('')
            end
            
        case 1 % detect hand
            I = cam.snapshot;
            transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
            BW = threshBoard(transImage);
            newNumPixels = numel(find(BW));
            metric = abs(newNumPixels - numPixels);
            if metric > 1500
                state = 2;
            end
            
        case 2 % hand removed, find placement
            I = cam.snapshot;
            transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
            BW = threshBoard(transImage);
            newNumPixels = numel(find(BW));
            metric = abs(newNumPixels - numPixels);
            
            if metric < 1500
                pause(0.75)
                I = cam.snapshot;
                currentImage = im2single(rgb2gray(I));
                diffImages = abs(refImage - currentImage);
                diffImages = medfilt2(diffImages);
                transImage = imwarp(diffImages,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
                diffMeans = calcSqaureMeans(transImage);
                currentImage = im2single(rgb2gray(I));
                
                disp(' ')
                disp('Hand removed')
                disp('Place new piece to detect')                
                numPixels = newNumPixels;
                refImage = currentImage;
                
                state = 0;
                [~, pos] = sort(diffMeans(:));
                pos = pos(end);
                if diffMeans(pos) > thresh
                    pieceNames(pos) = label(1);
                    if label(2) == 'w'
                        pieceNames(pos) = upper(pieceNames(pos));
                    end
                end
                
                if isPlot
                I = cam.snapshot;
                transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
                squareSize = Consts.SQUARESIZE;
                [x,y] = meshgrid((1:squareSize:8*squareSize) + round(squareSize/2), ...
                    (1:squareSize:8*squareSize) + round(squareSize/2));
                
                figure(2)
                subplot(1,3,2)
                imshow(transImage);
                pause(0.25)
                text(x(:),y(:),pieceNames,'HorizontalAlignment','center','FontSize', 20, 'Color','r' )
                end
            end
    end
end
end

function reset = trackMoves(cam, tform, pieceNames, whiteTurn, isPlot)

I = cam.snapshot;
transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
BW = threshBoard(transImage);
numPixels = numel(find(BW));
refImage = im2single(rgb2gray(I));

thresh = 0.03;

state = 0;
reset = false;

figure(4)
sgtitle('Game Tracking')
while true
    I = cam.snapshot;
    transImage = imwarp(I,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
    BW = threshBoard(transImage);
    newNumPixels = numel(find(BW));
    metric = abs(newNumPixels - numPixels);
    currentImage = im2single(rgb2gray(I));
    diffImages = abs(refImage - currentImage);
    diffImages = medfilt2(diffImages);
    transImage = imwarp(diffImages,tform,'OutputView',imref2d(Consts.BOARDSIZE * Consts.SQUARESIZE));
    diffMeans = calcSqaureMeans(transImage);
    
    
    % to exit hold your hand for 5 seconds
    if metric < 1500
        tic
    end
    
    time = toc;
    
    if time > 10
        button = questdlg('Stop Playing?', 'Exit', 'Yes', 'Not yet', 'Yes');
        if strcmp(button, 'Yes')
            break
        else
            tic
        end
    end
    
    if isPlot && state
        figure(4)
        subplot(1,2,1)
        imshow(diffImages,[])
        title('Diffrences Between Images')
    end
    
    switch state
        case 0 % track for hand appering
            if metric > 1500
                state = 1;
            end
            
        case 1 % wait until hand removed
            if metric < 1500
                state = 2;
            end
            
        case 2 % check for changes in board squares means
            [~, suspectedPos] = sort(diffMeans(:));
            suspectedPos = suspectedPos(end-1:end);
            if sum(diffMeans(suspectedPos) > thresh,'all') ~= 2
                state = 3;
            else
                state = 4;
            end
            
        case 3 % no move occours
            disp(' ')
            disp('Mo move was played')
            
            % update references
            numPixels = newNumPixels;
            refImage = currentImage;
            state = 0;
            
        case 4 % move occours
            [pos1, pos2] = deal(suspectedPos(1), suspectedPos(2));
            disp(' ')
            disp('Detecting move')
            if pieceNames(pos1) == ""
                [pos1, pos2] = deal(pos2, pos1);
            end
            
            % find the color of the piece in position 1
            if upper(pieceNames(pos1)) == pieceNames(pos1)
                whitePiece = true;
            else
                whitePiece = false;
            end
            
            % decied starting and ending points based on whos turn
            if ~xor(whiteTurn, whitePiece)
                startPos = pos1;
                endPos = pos2;
            else
                startPos = pos2;
                endPos = pos1;
            end
            
            newMove = pos2move(startPos, endPos);
%             iligalMove = checkIfValid(newMove);
            iligalMove = 0;
            
            if iligalMove
                disp('Wrong move! Please return the pieces to last position')
                state = 5;
            else
                % update references
                numPixels = newNumPixels;
                refImage = currentImage;
                
                [pieceNames(startPos), pieceNames(endPos)] = deal("",pieceNames(startPos));             
                
                whiteTurn = ~whiteTurn;
                disp(' ')
                disp(["Detected Move: " newMove])
                state = 0;
                
                if isPlot
                    squareNum = [startPos - 1, endPos - 1];
                    squares = cell(1,2);
                    for i = 1:2
                        squareSize = Consts.SQUARESIZE;
                        col = floor(squareNum(i)/8);
                        row = mod(squareNum(i),8);

                        southwest = transformPointsInverse(tform,[col, row + 1] * squareSize);
                        southeast = transformPointsInverse(tform,[col + 1, row + 1] * squareSize);
                        northwest = transformPointsInverse(tform,[col, row] * squareSize);
                        northeast = transformPointsInverse(tform,[col + 1, row] * squareSize);

                        squares{i} = [southwest northwest northeast southeast];
                    end
                    figure(4)
                    subplot(1,2,2)
                    imshow(I)
                    imshow(insertShape(I,'FilledPolygon',{ squares{1}, squares{2}},...
                    'Color', {'red','green'},'Opacity',0.4));
                    title('Tracked Move')
                end
            end
            
        case 5 % handle ilegal moves
            [~, suspectedPos] = sort(diffMeans(:));
            suspectedPos = suspectedPos(end-1:end);
            if sum(diffMeans(suspectedPos) > thresh,'all') ~= 2
                numPixels = newNumPixels;
                refImage = currentImage;
                disp(' ')
                disp('please continue')
                state = 0;
            end
    end
end

button = questdlg('Do you wish for a new game?','Game stopped','Yes','No','Yes');

inputFile = fopen('GUI/input.txt','a');
if strcmp(button, 'Yes')
    fprintf(inputFile, '%s\n', 'reset');
    reset = true;
else
    fprintf(inputFile, '%s\n', 'stop');    
end
fclose(inputFile);

end

% auxiliary functions
function BW = binBoard(image)
image = rgb2gray(image);
image = im2single(image);
image = medfilt2(image,[7,7]);
image = imgaussfilt(image,2,'FilterSize',7);
level = graythresh(image);
BW = imbinarize(image,level);
end

function means = calcSqaureMeans(image)
% This function calculates the mean value of each sqaure in a board
% image and returns 8x8 matrix means

% radius = floor(Consts.SQUARESIZE/5);
% pad = floor((Consts.SQUARESIZE - (2 * radius + 1))/2);
% kernel = fspecial('disk',radius);
% kernel = padarray(kernel,[pad,pad],0);
kernel = fspecial('average',Consts.SQUARESIZE);
means = blockproc(image, [Consts.SQUARESIZE,Consts.SQUARESIZE], ...
    @(block) conv2(block.data,kernel,'valid'),'BorderSize', [Consts.SQUARESIZE, Consts.SQUARESIZE],'TrimBorder', true);
end

function BW = threshBoard(image)
lab = rgb2lab(image);
BW = lab(:,:,1) > 55 & lab(:,:,2) > 6.5 & lab(:,:,2) < 24 & lab(:,:,3) > 0 & lab(:,:,3) < 20;
end

function board = defaultBoard()
% Board intialize example - starting position - default position
board(1:8,1:8) = "";

%White
board(1,1) = "r";
board(1,8) = "r";
board(1,2) = "n";
board(1,7) = "n";
board(1,6) = "b";
board(1,3) = "b";
board(1,4) = "q";
board(1,5) = "k";
board(2,:) = "p";

%Black
board(8,1) = "R";
board(8,8) = "R";
board(8,2) = "N";
board(8,7) = "N";
board(8,6) = "B";
board(8,3) = "B";
board(8,4) = "Q";
board(8,5) = "K";
board(7,:) = "P";
end

function fen = board2fen(board)
% This function gets an 8x8 string matrix represent the current board, and
% return a FEN string.
% We can use this function to start a game from any board position
% detected. An assumption is that the position is white to move.

fen = "";
freeSquares = 0;
rankFEN = "";
for i = 1:8
    for j = 1:8
        if (board(i,j)=="")
            freeSquares = freeSquares + 1;
        elseif (freeSquares ~= 0)
            rankFEN = rankFEN + int2str(freeSquares) + board(i,j);
            freeSquares = 0;
        else
            rankFEN = rankFEN + board(i,j);
        end
    end
    if (freeSquares ~= 0)
        rankFEN = rankFEN + int2str(freeSquares);
    end
    fen = fen + "/" + rankFEN;
    rankFEN = "";
    freeSquares = 0;
end

% delete the first '/' and add the missing FEN format parts
if (extractAfter(fen, "/") == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
    fen = extractAfter(fen,"/") + " w KQkq - 0 1"; 
    disp('Default position');
else
    fen = extractAfter(fen,"/") + " w - - 0 1"; 
    disp('Not default position');
end
end

function newMove = pos2move(startPos, endPos)
% This function will return the currect way to represent moves for the
% engine communiction (via the python code).
% input - 2 int numbers, represent the from & to squares as numbers from
% 1-64.
% output - UCI move, e.g. e2e4

% e.g. the detected move was from the 20 square to the 22 square
% rank 'a' in the chess board conatin square 1 to 8, rank b 9 to 16 etc. 
% the black side is the top one, and we start counting from there.
%      1     9    17    25    33    41    49    57
%      2    10    18    26    34    42    50    58
%      3    11    19    27    35    43    51    59
%      4    12    20    28    36    44    52    60
%      5    13    21    29    37    45    53    61
%      6    14    22    30    38    46    54    62
%      7    15    23    31    39    47    55    63
%      8    16    24    32    40    48    56    64
rank = ["a","b","c","d","e","f","g","h"];

column_from = ceil(startPos/8);
row_from = 9 - mod(startPos,8);
if (row_from == 9)
    row_from = 1;
end

column_to = ceil(endPos/8);
row_to = 9 - mod(endPos,8);
if (row_to == 9)
    row_to = 1;
end

newMove = rank(column_from) + num2str(row_from) + rank(column_to) + num2str(row_to);
end

% communication with python functions
function [illegalBoard] = displayBoard(fen)
% This function write the initial position detected to the python code
% and gets a legallity feedback of the inital position (legallity loop
% until the position is legal)
% Input :  fen -  Formal string represention of a position in chess
% Output : ilegalBoard - bolean flag   

% interpeter = "/Library/Frameworks/Python.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python";
% pythonFile = "'/Users/royschneider/Documents/Studies/Year D/Semester A/Digital Image Processing/Final Project/code/GUI/main.py'";
% commandStr =  interpeter + " " + pythonFile;
% system(commandStr);

inputFile = fopen('GUI/input.txt','a');
fprintf(inputFile, '%s\n', fen);
fclose(inputFile);

while true
    inputFile = fopen('GUI/output.txt','r');
    tline = fgetl(inputFile);
    if ischar(tline)
        illegalBoard = str2double(tline);
        inputFile = fopen('GUI/output.txt','w');
        fclose(inputFile);
        break
    end
    fclose(inputFile);
end
end

function [ilegalMove] = checkIfValid(newMove)
% This function write the initial position detected to the python code
% and gets a legallity feedback of the inital position (legallity loop
% until the position is legal)
% Input :  fen -  Formal string represention of a position in chess
% Output : ilegalBoard - bolean flag   
 
inputFile = fopen('GUI/input.txt','a');
fprintf(inputFile, '%s\n', newMove);
fclose(inputFile);
 
while true
    inputFile = fopen('GUI/output.txt','r');
    tline = fgetl(inputFile);
    if ischar(tline)
        ilegalMove = str2double(tline);
        inputFile = fopen('GUI/output.txt','w');
        fclose(inputFile);
        break
    end
    fclose(inputFile);
end
end
