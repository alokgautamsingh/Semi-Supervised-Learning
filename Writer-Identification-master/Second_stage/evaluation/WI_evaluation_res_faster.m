clc;clear all;close all;
addpath ../test
addpath ..
addpath CM_Curve
%netStruct = load('../data/res52_drop0.75_batch16_psudo_label/net-epoch-25.mat');
%netStruct.net.layers(end-3)=[];
%netStruct.net.vars(178)=[];
%net = dagnn.DagNN.loadobj(netStruct.net);
%net.addLayer('feature',dagnn.Concat('dim',3),{'pool5','pool5_local'},{'pool5_fine'});
%net.mode = 'test' ;
%net.move('gpu') ;
rank_size = 200;
%net.conserveMemory = false;
%im_mean = net.meta.normalization.averageImage;
%im_mean = imresize(im_mean,[224,224]);

%% add necessary paths
query_dir = 'D:/Writer identification/data/HistoricalWI_Query_binary/';% query directory
test_dir = 'D:/Writer identification/data/HistoricalWI_Test_binary_new/';% database directory

%% calculate query features
Hist_query = importdata('../test/HistoricalWI_bianry_resnet_query_drop0.25_E150.mat')';
nQuery = size(Hist_query, 2);
%nQuery=3600;
%% calculate database features
Hist_test = importdata('../test/HistoricalWI_binary_resnet_gallery_drop0.25_E150.mat')';
nTest = size(Hist_test, 2);

%% calculate the ID and camera for database images
%mkdir('./data')
test_files = dir([test_dir '*.jpg']);
testID = zeros(length(test_files), 1);
%testCAM = zeros(length(test_files), 1);
if ~exist('data/testID_new.mat')
    for n = 1:length(test_files)
        img_name = test_files(n).name;
        testID(n) = str2num(img_name(1:4));
        % if strcmp(img_name(1), '-') % junk images
            % testID(n) = -1;
            % testCAM(n) = str2num(img_name(5));
        % else
            % %img_name
            % testID(n) = str2num(img_name(1:4));
            % testCAM(n) = str2num(img_name(7));
        % end
    end
    save('data/testID_new.mat', 'testID');
    %save('data/testCAM.mat', 'testCAM');
else
    testID = importdata('data/testID_new.mat');
    %testCAM = importdata('data/testCAM.mat');    
end

%% calculate the ID and camera for query images
query_files = dir([query_dir '*.jpg']);
queryID = zeros(length(query_files), 1);
%queryCAM = zeros(length(query_files), 1);
if ~exist('data/queryID_new.mat')
    for n = 1:length(query_files)
        img_name = query_files(n).name;
        queryID(n) = str2num(img_name(1:4));
        % if strcmp(img_name(1), '-') % junk images
            % queryID(n) = -1;
            % queryCAM(n) = str2num(img_name(5));
        % else
            % queryID(n) = str2num(img_name(1:4));
            % queryCAM(n) = str2num(img_name(7));
        % end
    end
    save('data/queryID_new.mat', 'queryID');
    %save('data/queryCAM.mat', 'queryCAM');
else
    queryID = importdata('data/queryID_new.mat');
    %queryCAM = importdata('data/queryCAM.mat');    
end

%% search the database and calcuate re-id accuracy
ap = zeros(nQuery, 1); % average precision
ap_max_rerank  = zeros(nQuery, 1); % average precision with MultiQ_max + re-ranking 
ap_pairwise = zeros(nQuery, 5); % pairwise average precision with single query (see Fig. 7 in the paper)

CMC = zeros(nQuery, rank_size);
CMC_max_rerank = zeros(nQuery, rank_size);

r1 = 0; % rank 1 precision with single query
r1_max_rerank = 0; % rank 1 precision with MultiQ_max + re-ranking
r1_pairwise = zeros(nQuery, 5);% pairwise rank 1 precision with single query (see Fig. 7 in the paper)

dist3600_3600=sqdist(Hist_test,Hist_test);
dist = sqdist(Hist_test, Hist_query); % distance calculate with single query. Note that Euclidean distance is equivalent to cosine distance if vectors are l2-normalized
%dist_cos_max = (2-dist_max)./2; % cosine distance with MultiQ_max, used for re-ranking

knn = 1; % number of expanded queries. knn = 1 yields best result
%queryCam = importdata('data/queryCAM_duke.mat'); % camera ID for each query
%testCam = importdata('data/testCAM_duke.mat'); % camera ID for each database image
true_image=zeros(5,nQuery);
rank_index=zeros(rank_size,nQuery);
for k = 1:nQuery
    % load ground truth for each query (good and junk)
    %good_index = intersect(find(testID == queryID(k)), find(testCAM ~= queryCAM(k)))';% images with the same ID but different camera from the query
    good_index = find(testID == queryID(k));
    % junk_index1 = find(testID == -1);% images neither good nor bad in terms of bbox quality
    % junk_index2 = intersect(find(testID == queryID(k)), find(testCAM == queryCAM(k))); % images with the same ID and the same camera as the query
    % junk_index = [junk_index1; junk_index2]';
    score = dist(:, k);
    %score_avg = dist_avg(:, k); 
    %score_max = dist_max(:, k);
    
    % sort database images according Euclidean distance
    [~, index] = sort(score, 'ascend');  % single query
    
    % re-rank  select rank_size=1000 index
    index = index(1:rank_size);    
    true_image(:,k)=good_index;
    rank_index(:,k)=index;
    [ap(k), CMC(k, :)] = compute_AP_rerank(good_index,index);% compute AP for single query
    %ap_pairwise(k, :) = compute_AP_multiCam(good_index, junk_index1,junk_index2, index, queryCAM(k), testCAM); % compute pairwise AP for single query
    fprintf('%d::%d::%f\n',k,testID(k),ap(k));
    %%%%%%%%%%% calculate pairwise r1 precision %%%%%%%%%%%%%%%%%%%%
    %r1_pairwise(k, :) = compute_r1_multiCam(good_index, junk_index1,junk_index2, index, queryCAM(k), testCAM); % pairwise rank 1 precision with single query
    %%%%%%%%%%%%%% calculate r1 precision %%%%%%%%%%%%%%%%%%%%
end
CMC = mean(CMC);
%% print result
fprintf('single query:                                    mAP = %f, r1 precision = %f\r\n', mean(ap), CMC(2));
%[ap_CM, r1_CM] = draw_confusion_matrix(ap_pairwise, r1_pairwise, queryCam);
%fprintf('average of confusion matrix with single query:  mAP = %f, r1 precision = %f\r\n', (sum(ap_CM(:))-sum(diag(ap_CM)))/30, (sum(r1_CM(:))-sum(diag(r1_CM)))/30);

%% plot CMC curves
figure;
s = rank_size;
CMC_curve = CMC ;
plot(1:s, CMC_curve(:, 1:s));
plot(1:s, CMC_curve(:, 1:s));
