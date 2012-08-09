function [ f_fname_e,g_fname_e,dim_e,options_e,fb_e ] = makeExtendedModel(dim,options,in_sessions)
% This function creates the description files of an Extended Model (EM)
% of an Initial Model (IM).
% The output of the EM is the concatenation of independant outputs of several IM models
% which may share parameters (evolution or observation parameters)

% The purpose of this function in the context of behavioral experiments is
% to have a generative modei for multiple independant sessions.
% IM : generative models for a single session
% EM : generative model for multiple sessions


% INPUT
% - dim : dimensions of the IM
%    - .u : dimension of the data vector used
% - options : options of the IM
%    - .dim_e : if exist, specifies dimension of the parameter space of the EM
% - in_sessions : information about sessions
%       - .f_fname : evolution function of the IM
%       - .g_fname : observation function of the IM model
%       - .dim : dimensions of the variables of the model for a single
%       session (base model)
%       - .ind.theta : indices of the variable theta used for each session
%       - .ind.phi : indices of the variable phi used for each session
% - y : ((dim_output*Nsession)*Ntrials) Output of all sessions concatenated
% - u : ((dim_data*Nsession)*Ntrials) Experimenter data of all sessions
%       concatenated
% - isYout : ((dim_output*Nsession)*Ntrials) behavioral data not to be
%           considered for inversion (1=out,0=in), concatenated for all
%           sessions
% - priors: a structure containing the parameters of the prior pdf of the
% extended model :
%       .muPhi: a n_phix1 vector containing the prior mean of Phi, the
%       observation parameters
%       .muTheta: a n_thetax1 vector containing the prior mean of Theta,
%       the evolution parameters
%       .muX0: a nx1 vector containing the prior mean of the hidden-states
%       initial condition
%       .SigmaPhi: n_phixn_phi prior covariance matrix of Phi
%       .SigmaTheta: n_thetaxn_theta prior covariance matrix of Theta
%       .SigmaX0: nxn prior covariance matrix of X0
%       .a_sigma / .b_sigma: the shape and scale parameters of the prior
%       Gamma pdf upon the measurement noise precision
%       .a_alpha / .b_alpha: the shape and scale parameters of the prior
%       Gamma pdf upon the stochastic innovations precision

%}


n_sess = in_sessions.n_sess;
%---------------------------------------------------
%-- Dimensions of the extended model


dim_e = struct();
dim_e.p = dim.p*n_sess; % output
dim_e.n_t = dim.n_t; % number of trials (unchanged)
dim_e.u = dim.u*n_sess; % number of trials (unchanged)
dim_e.n = dim.n*n_sess; % hidden states
dim_e.n_sess = n_sess;

%-- Parameters
%- theta
try
    dim_e.n_theta = in_sessions.dim_e.n_theta;
catch
    dim_e.n_theta = dim.n_theta*n_sess;
    in_sessions.ind.theta = reshape(1:dim_e.n_theta,n_sess,dim.n_theta);
end
%- phi
try
    dim_e.n_phi = in_sessions.dim_e.n_phi;
catch
    dim_e.n_phi = dim.n_phi*n_sess;
    in_sessions.ind.phi = reshape(1:dim_e.n_phi,n_sess,dim.n_phi);
end

%------------------------------------------------------
%-- Filling session structure

% --- General information for all sessions
in = struct();
in.nsess = in_sessions.n_sess;


% --- Specific information for each session
i_gx = 0; % cumulated index of output
i_x = 0; % cumulated index of hidden states
i_u = 0; % cumulated index of inputs

for i = 1 : n_sess
    
    
    try dim_s = dim{i};
    catch; dim_s = dim;end
    
    
    % Information about the evolution/obsevation function for each session
    try in.sess(i).f_fname = in_sessions.f_fname{i};
    catch; in.sess(i).f_fname = in_sessions.f_fname;end
    try  in.sess(i).g_fname = in_sessions.g_fname{i};
    catch ;in.sess(i).g_fname = in_sessions.g_fname;end
    
    
    % Information about the evolution/obsevation function for each session
    in.sess(i).f_fname = in_sessions.f_fname; % the function to be used for each session
    in.sess(i).g_fname = in_sessions.g_fname;
    
    % Information about indices of parameters, hidden states and output used by
    % each session
    %     in.sess(i).ind.x = dim_s.n*(i-1)+1:dim_s.n*i;
    %     in.sess(i).ind.gx = dim_s.p*(i-1)+1:dim_s.p*i;
    %     in.sess(i).ind.u = dim_s.u*(i-1)+1:dim_s.u*i;
    %
    in.sess(i).ind.x = i_x+1:i_x+dim_s.n;   i_x = i_x + dim_s.n;
    in.sess(i).ind.gx = i_gx+1:i_gx+dim_s.p;   i_gx = i_gx + dim_s.p;
    in.sess(i).ind.u = i_u+1:i_u+dim_s.u;   i_u = i_u + dim_s.u;
    
    % Information about the evolution/obsevation paramaters for each session
    if isempty(in_sessions.ind.theta)
        in.sess(i).ind.theta = [];
    else in.sess(i).ind.theta = in_sessions.ind.theta(i,:); end
    if isempty(in_sessions.ind.phi)
        in.sess(i).ind.phi = [];
    else in.sess(i).ind.phi = in_sessions.ind.phi(i,:); end
    
    % Information about the evolution/obsevation extra input for each session
    try in.sess(i).inG = in_sessions.inG{i};
    catch; in.sess(i).inG = in_sessions.inG;end
    try  in.sess(i).inF = in_sessions.inF{i};
    catch ;in.sess(i).inF = in_sessions.inF;end
    
end

%------------------------------------------------------
%---- Options
options_e = options; % copy all options then modify

options_e.inF = in;
options_e.inG = in;

options_e.inG.dim = dim_e; % requested to know size of output when generating it.
options_e.dim = dim_e;


options_e.GnFigs = 0;
try options_e.binomial = in_sessions.binomial;
catch; options_e.binomial = 0; end % default is continuous data
try  options_e.DisplayWin = in_sessions.DisplayWin;
catch ; options_e.DisplayWin = 1; end


options_e.isYout = zeros(dim_e.p,dim_e.n_t); 


%---- Function handles

f_fname_e = @f_nsess;
g_fname_e = @g_nsess;


%
%---- Handle for simulation
fb_e = [];
try
    
    %fb = options.fb;
    fb_e = struct('h_fname',@h_nsess,...
        'nsess',n_sess);
    fb_e.inH.indy = [];
    fb_e.inH.indfb = [];
    i_fb = 0;
    for i = 1 : n_sess
        
        % possible different models for each session
        try dim_s = dim{i};
        catch; dim_s = dim;end
        try fb_s = in_sessions.fb{i};
        catch; fb_s = in_sessions.fb;end
        
        fb_e.inH.sess(i).h_fname = fb_s.h_fname; % handle corresponding to session
        fb_e.inH.sess(i).indy = in.sess(i).ind.gx(fb_s.indy);
        fb_e.inH.sess(i).indfb = i_fb + [1:length(fb_s.indfb)]'; % index in the extended feedback vector (not in u!)
        
        try   fb_e.inH.sess(i).inH =  in_sessions.inH{i}; % case feedbacks not concatenated
        catch;  fb_e.inH.sess(i).inH =  in_sessions.inH(fb_e.inH.sess(i).indfb,:); end % case feedbacks concatenated
        
        
        fb_e.inH.indy = [fb_e.inH.indy; in.sess(i).ind.u(fb_s.indy)];
        fb_e.inH.indfb = [fb_e.inH.indfb; in.sess(i).ind.u(fb_s.indfb)];
        i_fb =i_fb+length(fb_s.indfb);

        % fb_e.inH.sess(i).indfb = in.sess(i).ind.u(fb_s.indfb);
        % fb_e.inH.indy = [fb_e.inH.indy; fb_e.inH.sess(i).indy];
        % fb_e.inH.sess(i).indy = fb.indy + dim.p*(i-1);
        % fb_e.inH.sess(i).indgx = dim.p*(i-1)+1:dim.p*i;
        % fb_e.inH.sess(i).indy = fb.indy + dim.p*(i-1);
        % fb_e.inH.sess(i).indfb = fb.indfb+  dim.u*(i-1);
        
    end
    
    fb_e.inH.nsess = n_sess; % number of sessions
    fb_e.indy =fb_e.inH.indy;
    fb_e.indfb =fb_e.inH.indfb;
    

    %  fb_e.inH.dim_fb = length(fb.indfb)*n_sess; % total size of feedback
    %  fb_e.inH.dim_fb = length(fb.indfb)*n_sess; % total size of feedback
    %  fb_e.inH.dim_singlefb = length(fb.indfb);
    %  fb_e.indy = fb.indy + dim.u*([1 : n_sess]-1); % this is where to store y in u
    %  fb_e.indfb =  repmat(fb.indfb,n_sess,1) +
    %  dim.u*([0:n_sess-1]')*(ones(size(fb.indfb)))%-1%([1 : n_sess]-1); %
    %  this is where to store feedback in u
    
    
    
catch;
end
    options_e.fb = fb_e;


end






