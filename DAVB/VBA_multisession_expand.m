function [f_fname_multi,g_fname_multi,dim_multi,options,u_multi] = VBA_multisession_expand(f_fname,g_fname,dim,options,u)


%% check args

%% check if multisession is required
if ~isfield(options,'multisession') || ~isfield(options.multisession,'split') || numel(options.multisession.split) < 2 ... % no need for multisession
        || (isfield(options.multisession,'expanded') && options.multisession.expanded) % already went there before, no need to expand again
    f_fname_multi = f_fname;
    g_fname_multi = g_fname;
    dim_multi = dim;
    u_multi = u;
    return;
end

    
%% extract sessions
if sum(options.multisession.split) ~= dim.n_t
    error('*** Multisession: partition covers %d datapoints but data has %d.',sum(options.multisession.split),dim.n_t);
end

n_session = numel(options.multisession.split);
session_id = ones(1,dim.n_t);
for i=cumsum(options.multisession.split)
    session_id(i+1:end) = session_id(i+1:end) + 1;
end

% = append session number to inputs
if options.microU
    session_id = repmat(session_id,decim,1);
    session_id = session_id(:)';
end

dim_multi = dim;

u_multi = [u; session_id] ;
dim_multi.u = dim.u+1 ;


%% duplicate parameters
priors_multi = options.priors;

% = get indexes of duplicated parameters
X0_multi = 1:dim.n;
theta_multi = 1:dim.n_theta;
phi_multi = 1:dim.n_phi;

% = restrict fixed parameters
if isfield(options.multisession,'fixed') 
    if isfield(options.multisession.fixed,'theta')
        theta_multi = setdiff(theta_multi,options.multisession.fixed.theta);
    end
    if isfield(options.multisession.fixed,'phi')
        phi_multi = setdiff(phi_multi,options.multisession.fixed.phi);
    end
end

% = expand (duplicate) priors and dimensions to cover all sessions
priors = options.priors;

[priors_multi.muX0, priors_multi.SigmaX0, dim_multi.n] ...
    = expand_param(priors.muX0,priors.SigmaX0,X0_multi,n_session) ;

[priors_multi.muTheta, priors_multi.SigmaTheta, dim_multi.n_theta] ...
    = expand_param(priors.muTheta,priors.SigmaTheta,theta_multi,n_session) ;

[priors_multi.muPhi, priors_multi.SigmaPhi, dim_multi.n_phi] ...
    = expand_param(priors.muPhi,priors.SigmaPhi,phi_multi,n_session) ;


% = restrict initial hidden states
if isfield(options.multisession,'fixed') && isfield(options.multisession.fixed,'X0')
    % enforce covariance across states (duplication is needed for evolution
    % independance)
    for i= options.multisession.fixed.X0
        X0_cor = i + (0:n_session-1)*dim.n;
        priors_multi.SigmaX0(X0_cor,X0_cor) = priors_multi.SigmaX0(i,i);
    end
    
end

options.priors = priors_multi;
if isfield(options,'dim')
    options=rmfield(options,'dim');
end

% = precompute param indexes for each session
indices.X0 = param_indices(dim.n,X0_multi,n_session);
indices.theta = param_indices(dim.n_theta,theta_multi,n_session);
indices.phi = param_indices(dim.n_phi,phi_multi,n_session);

multisession.indices = indices;
multisession.indices = indices;

%% set new evolution and observation functions

multisession.dim = dim_multi;
multisession.X0_multi = X0_multi;
multisession.theta_multi = theta_multi;
multisession.phi_multi = phi_multi;
multisession.expanded = true;

options.inF.multisession = multisession ;
options.inG.multisession = multisession ;

options.inF.multisession.f_fname = f_fname;
options.inG.multisession.g_fname = g_fname;

f_fname_multi = @f_multi;
g_fname_multi = @g_multi;

options.multisession.expanded = true;
end

%% wrappers for evolution observation functions 

% = wrapper for the evolution function
function  [fx,dF_dX,dF_dTheta] = f_multi(Xt,Theta,ut,in)
    
    % extract session wise states and params
    idx_X0 = in.multisession.indices.X0(:,ut(end));
    idx_theta = in.multisession.indices.theta(:,ut(end));
    
    % call original function
    nout = nargout(in.multisession.f_fname);
    [output{1:nout}] = feval(in.multisession.f_fname, ...
    Xt(idx_X0), ...
    Theta(idx_theta), ...
    ut(1:end-1),...
    in) ;

    % store evolution
    fx = zeros(in.multisession.dim.n,1);
    fx(idx_X0) = output{1};
      
    % store derivatives if possible
    if nout>=2
        dF_dX = zeros(in.multisession.dim.n,in.multisession.dim.n);
        dF_dX(idx_X0,idx_X0) = output{2} ;
    else
        dF_dX = [];
    end
    
    if nout>=3
        dF_dTheta = zeros(in.multisession.dim.n_theta,in.multisession.dim.n);
        dF_dTheta(idx_theta,idx_X0) = output{3} ;
    else
        dF_dTheta = [];
    end
    
end

% = wrapper for the observation function
function  [gx,dG_dX,dG_Phi] = g_multi(Xt,Phi,ut,in)
    
    % extract session wise states and params
    idx_X0 = in.multisession.indices.X0(:,ut(end));
    idx_phi = in.multisession.indices.phi(:,ut(end));
    
    % call original function
    nout = nargout(in.multisession.g_fname);
    [output{1:nout}] = feval(in.multisession.g_fname, ...
    Xt(idx_X0), ...
    Phi(idx_phi), ...
    ut(1:end-1),...
    in) ;

    % store observation
    gx = output{1};
    
    % store derivatives if possible
    if nout>=2
        dG_dX = zeros(in.multisession.dim.n,numel(gx));
        dG_dX(idx_X0,:) = output{2} ;
    else
        dG_dX = [];
    end
    
    if nout>=3
        dG_Phi = zeros(in.multisession.dim.n_phi,numel(gx));
        dG_Phi(idx_phi,:) = output{3} ;
    else
        dG_Phi = [];
    end
    
end

%% some shortcuts
function [mu_multi,sigma_multi,dim_multi] = expand_param(mu,sigma,idx,n_session)
% concatenate priors means and variances accross sessions

% = initial and ifnal dimensions
n1 = numel(mu);
n2 = n1 + (n_session-1)*numel(idx);

% = means
mu = mu(:);
mu_multi = [mu ; repmat(mu(idx),n_session-1,1)];

% = variances
sigma_temp = kron(eye(n_session-1), sigma(idx,idx));
sigma_multi = [sigma,           zeros(n1,n2-n1);
               zeros(n2-n1,n1)  sigma_temp];

% = dimension          
dim_multi = n2;                    
                    
end

function indices = param_indices(n,idx,n_session)
% return for each session (column) the indices of n parameters in the 
% expanded priorsgiven only those in idx are duplicated

indices = repmat(1:n,n_session,1)';
for k=2:n_session
    indices(idx,k) = (k-1)*n + (1:numel(idx));
end

end

